#include "cache.h"
#include "blame-tree.h"
#include "quote.h"
#include "parse-options.h"

static void show_entry(const char *path, const struct commit *commit, void *d)
{
	printf("%s\t", oid_to_hex(&commit->object.oid));
	write_name_quoted(path, stdout, '\n');
	fflush(stdout);
}

int cmd_blame_tree(int argc, const char **argv, const char *prefix)
{
	struct blame_tree bt;

	git_config(git_default_config, NULL);

	blame_tree_init(&bt, argc, argv);
	if (blame_tree_run(&bt, show_entry, NULL) < 0)
		die("error running blame-tree traversal");
	blame_tree_release(&bt);

	return 0;
}
