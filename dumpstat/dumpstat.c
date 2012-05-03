#include "cache.h"
#include "dumpstat.h"
#include "strbuf.h"
#include "quote.h"
#include "config.h"

static struct dumpstat *vars;
static struct dumpstat **vars_tail = &vars;

static int in_use = -1;
static int received_dump_signal;
static int streaming;
static struct dumpstat_writer *writer;
static struct dumpstat_formatter *formatter;

static void handle_dump_signal(int sig)
{
	received_dump_signal = 1;
}

static void dumpstat_default_vars(void)
{
	static struct dumpstat pid = DUMPSTAT_INIT("pid");

	dumpstat_uint(&pid, getpid());
}

static struct dumpstat_writer *parse_writer(const char *s)
{
	if (!s)
		return NULL;

	if (starts_with(s, "file:"))
		return dumpstat_to_file(s + 5);
	else if (s[0] == '/')
		return dumpstat_to_file(s);

	warning("unknown dumpstat type: %s", s);
	return NULL;
}

static struct dumpstat_formatter *parse_formatter(const char *s)
{
	if (!s || !strcmp(s, "json"))
		return dumpstat_format_json();

	warning("unknown dumpstat format: %s", s);
	return NULL;
}

static int dumpstat_init(void)
{
	if (in_use == -1) {
		writer = parse_writer(getenv("DUMPSTAT"));
		formatter = parse_formatter(getenv("DUMPSTAT_FORMAT"));
		if (writer && formatter) {
			in_use = 1;
			streaming = git_env_bool("DUMPSTAT_STREAM", 0);
			signal(SIGURG, handle_dump_signal);
			dumpstat_default_vars();
		}
		else
			in_use = 0;
	}

	return in_use;
}

static int dumpstat_generic(struct dumpstat *ds, enum dumpstat_type type)
{
	if (!dumpstat_init())
		return 0;

	if (!ds->initialized) {
		*vars_tail = ds;
		vars_tail = &ds->next;
		ds->next = NULL;
		ds->initialized = 1;
	}

	if (ds->type != type) {
		memset(&ds->v, 0, sizeof(ds->v));
		ds->type = type;
	}

	return 1;
}

static int dumpstat_ready(struct dumpstat *ds)
{
	switch (ds->type) {
	case DUMPSTAT_UINT:
		return ds->v.uint.cur > ds->v.uint.sent + ds->v.uint.freq;
	default:
		return 1;
	}
}

static void dumpstat_write(struct dumpstat *ds)
{
	formatter->start();
	if (ds)
		formatter->add(ds);
	else {
		for (ds = vars; ds; ds = ds->next)
			formatter->add(ds);
	}
	formatter->finish();

	if (writer->write(formatter->buf, formatter->len) < 0)
		in_use = 0;
}

void dumpstat_flush(struct dumpstat *ds)
{
	if (!in_use)
		return;

	if (received_dump_signal) {
		dumpstat_write(NULL);
		received_dump_signal = 0;
	}
	else if (streaming && dumpstat_ready(ds))
		dumpstat_write(ds);
}

void dumpstat_identity(const char *value)
{
	static struct dumpstat id = DUMPSTAT_INIT("program");
	dumpstat_string(&id, value);
}

void dumpstat_string(struct dumpstat *ds, const char *value)
{
	if (!dumpstat_generic(ds, DUMPSTAT_STRING))
		return;
	ds->v.string = value;
	dumpstat_flush(ds);
}

void dumpstat_uint(struct dumpstat *ds, uintmax_t value)
{
	if (!dumpstat_generic(ds, DUMPSTAT_UINT))
		return;
	ds->v.uint.cur = value;
	dumpstat_flush(ds);
}

void dumpstat_increment(struct dumpstat *ds, uintmax_t value, uintmax_t freq)
{
	if (!dumpstat_generic(ds, DUMPSTAT_UINT))
		return;
	ds->v.uint.cur += value;
	ds->v.uint.freq = freq;
	dumpstat_flush(ds);
}

void dumpstat_bool(struct dumpstat *ds, int value)
{
	if (!dumpstat_generic(ds, DUMPSTAT_BOOL))
		return;
	ds->v.boolean = value;
	dumpstat_flush(ds);
}
