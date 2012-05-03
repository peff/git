#include "cache.h"
#include "dumpstat/dumpstat.h"

static void dumpstat_json_start(void);
static void dumpstat_json_add(const struct dumpstat *);
static void dumpstat_json_finish(void);

static struct strbuf buf = STRBUF_INIT;
static struct dumpstat_formatter format_json = {
	dumpstat_json_start,
	dumpstat_json_add,
	dumpstat_json_finish,
};

static void quote_json(struct strbuf *out, const char *v)
{
	static const char hex[] = "0123456789abcdef";

	if (!v) {
		strbuf_addstr(out, "null");
		return;
	}

	strbuf_addch(out, '"');
	while (*v) {
		unsigned char c = *v++;
		switch (c) {
		case '"':
		case '\\':
			strbuf_addch(out, '\\');
			strbuf_addch(out, c);
			break;
		case '\b':
			strbuf_addstr(out, "\\b");
			break;
		case '\f':
			strbuf_addstr(out, "\\f");
			break;
		case '\n':
			strbuf_addstr(out, "\\n");
			break;
		case '\r':
			strbuf_addstr(out, "\\r");
			break;
		case '\t':
			strbuf_addstr(out, "\\t");
			break;
		default:
			if (c < 32) {
				strbuf_addstr(out, "\\u00");
				strbuf_addch(out, hex[c >> 4]);
				strbuf_addch(out, hex[c & 0xf]);
			}
			else
				strbuf_addch(out, c);
		}
	}
	strbuf_addch(out, '"');
}

static void dumpstat_json_start(void)
{
	strbuf_reset(&buf);
}

static void dumpstat_json_finish(void)
{
	strbuf_addstr(&buf, "\n}\n");
	format_json.buf = buf.buf;
	format_json.len = buf.len;
}

static void dumpstat_json_add(const struct dumpstat *ds)
{
	if (buf.len)
		strbuf_addstr(&buf, ",\n  ");
	else
		strbuf_addstr(&buf, "{\n  ");
	quote_json(&buf, ds->name);
	strbuf_addstr(&buf, ": ");

	switch (ds->type) {
	case DUMPSTAT_STRING:
		quote_json(&buf, ds->v.string);
		break;
	case DUMPSTAT_BOOL:
		strbuf_addstr(&buf, ds->v.boolean ? "true" : "false");
		break;
	case DUMPSTAT_UINT:
		strbuf_addf(&buf, "%"PRIuMAX, ds->v.uint.cur);
		break;
	}
}

struct dumpstat_formatter *dumpstat_format_json(void)
{
	return &format_json;
}
