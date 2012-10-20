#include "cache.h"
#include "blame-tree.h"
#include "quote.h"
#include "parse-options.h"

static void show_entry(const char *path, const struct commit *commit, void *d)
{
	struct blame_tree *bt = d;

	if (commit->object.flags & BOUNDARY)
		putchar('^');
	printf("%s\t", oid_to_hex(&commit->object.oid));

	if (bt->rev.diffopt.line_termination)
		write_name_quoted(path, stdout, '\n');
	else
		printf("%s%c", path, '\0');

	fflush(stdout);
}

int cmd_blame_tree(int argc, const char **argv, const char *prefix)
{
	struct blame_tree bt;

	git_config(git_default_config, NULL);

	blame_tree_init(&bt, argc, argv, prefix);
	if (blame_tree_run(&bt, show_entry, &bt) < 0)
		die("error running blame-tree traversal");
	blame_tree_release(&bt);

	return 0;
}
