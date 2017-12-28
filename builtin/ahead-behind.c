#include "cache.h"
#include "commit.h"
#include "dir.h"
#include "commit.h"
#include "revision.h"
#include "remote.h"
#include "builtin.h"
#include "parse-options.h"
#include "pack-bitmap.h"

static const char * const ahead_behind_usage[] = {
	N_("git ahead-behind [--base=branch] [other...]"),
	NULL
};

static struct commit *default_base = NULL;
static const char *base_ref = "master";

static struct commit *get_commit(const char *str)
{
	struct commit *c = lookup_commit_reference_by_name(str);
	if (!c)
		die("bad revision '%s'", str);
	return c;
}

static void handle_arg(char *arg)
{
	struct commit *tip, *base;
	char *dotdot;
	int ahead, behind;

	dotdot = strstr(arg, "..");
	if (dotdot) {
		*dotdot = '\0';
		base = get_commit(dotdot + 2);
	} else {
		if (!default_base)
			default_base = get_commit(base_ref);
		base = default_base;
	}
	tip = get_commit(arg);

	revision_ahead_behind(tip, base, &ahead, &behind, AHEAD_BEHIND_FULL);
	printf("%s %d %d\n", arg, ahead, behind);
}

int cmd_ahead_behind(int argc, const char **argv, const char *prefix)
{
	int from_stdin = 0;

	struct option ahead_behind_opts[] = {
		OPT_STRING('b', "base", &base_ref, N_("base"), N_("base reference to process")),
		OPT_BOOL( 0 , "stdin", &from_stdin, N_("read rev names from stdin")),
		OPT_END()
	};

	argc = parse_options(argc, argv, NULL, ahead_behind_opts,
			     ahead_behind_usage, 0);

	if (from_stdin) {
		struct strbuf line = STRBUF_INIT;

		while (strbuf_getline(&line, stdin) != EOF) {
			if (!line.len)
				break;

			handle_arg(line.buf);
		}

		strbuf_release(&line);
	} else {
		int i;

		for (i = 0; i < argc; ++i) {
			char *arg = xstrdup(argv[i]);
			handle_arg(arg);
			free(arg);
		}
	}

	return 0;
}
