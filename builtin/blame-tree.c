#include "cache.h"
#include "blame-tree.h"
#include "quote.h"
#include "parse-options.h"

static int porcelain;
static const struct option options[] = {
	OPT_BOOL(0, "porcelain", &porcelain, "machine-readable output"),
	OPT_END()
};
static const char *blame_tree_usage[] = {
	"git blame-tree [options] [rev-opts] [rev] [--] [pathspec]",
	NULL
};

static void show_human_readable(const char *path, const char *orig_path,
				struct commit *commit, void *data)
{
	printf("%s\t", oid_to_hex(&commit->object.oid));
	write_name_quoted(path, stdout, '\n');
}

static void show_porcelain(const char *path, const char *orig_path,
			   struct commit *commit, void *data)
{
	printf("%s\t", oid_to_hex(&commit->object.oid));
	write_name_quoted(path, stdout, '\n');
	printf("filename ");
	write_name_quoted(orig_path, stdout, '\n');
	/* XXX should write more commit info here, but we need to
	 * factor the writing out of builtin/blame.c */
	maybe_flush_or_die(stdout, "stdout");
}

int cmd_blame_tree(int argc, const char **argv, const char *prefix)
{
	struct blame_tree bt;
	struct parse_opt_ctx_t ctx;

	git_config(git_default_config, NULL);
	blame_tree_init(&bt, prefix);

	parse_options_start(&ctx, argc, argv, prefix, options,
			    PARSE_OPT_KEEP_DASHDASH | PARSE_OPT_KEEP_ARGV0);
	for (;;) {
		switch (parse_options_step(&ctx, options, blame_tree_usage)) {
		case PARSE_OPT_HELP:
			exit(129);
		case PARSE_OPT_DONE:
			goto parse_done;
		}
		parse_revision_opt(&bt.rev, &ctx, options, blame_tree_usage);
	}
parse_done:
	argc = parse_options_end(&ctx);
	blame_tree_finish_setup(&bt, argc, argv);

	if (blame_tree_run(&bt, porcelain ? show_porcelain : NULL, NULL) < 0)
		die("error running blame-tree traversal");
	if (!porcelain)
		blame_tree_show(&bt, show_human_readable, NULL);

	blame_tree_release(&bt);
	return 0;
}
