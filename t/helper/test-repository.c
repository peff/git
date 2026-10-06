#define USE_THE_REPOSITORY_VARIABLE

#include "test-tool.h"
#include "commit-graph.h"
#include "commit.h"
#include "environment.h"
#include "hex.h"
#include "object.h"
#include "run-command.h"
#include "refs.h"
#include "lockfile.h"
#include "path.h"
#include "repository.h"
#include "setup.h"
#include "tree.h"

static void test_parse_commit_in_graph(const char *gitdir, const char *worktree,
				       const struct object_id *commit_oid)
{
	struct repository r;
	struct commit *c;
	struct commit_list *parent;

	if (repo_init(&r, gitdir, worktree))
		die("Couldn't init repo");

	repo_set_hash_algo(the_repository, hash_algo_by_ptr(r.hash_algo));

	c = lookup_commit(&r, commit_oid);

	if (!parse_commit_in_graph(&r, c))
		die("Couldn't parse commit");

	printf("%"PRItime, c->date);
	for (parent = c->parents; parent; parent = parent->next)
		printf(" %s", oid_to_hex(&parent->item->object.oid));
	printf("\n");

	repo_clear(&r);
}

static void test_get_commit_tree_in_graph(const char *gitdir,
					  const char *worktree,
					  const struct object_id *commit_oid)
{
	struct repository r;
	struct commit *c;
	struct tree *tree;

	if (repo_init(&r, gitdir, worktree))
		die("Couldn't init repo");

	repo_set_hash_algo(the_repository, hash_algo_by_ptr(r.hash_algo));

	c = lookup_commit(&r, commit_oid);

	/*
	 * get_commit_tree_in_graph does not automatically parse the commit, so
	 * parse it first.
	 */
	if (!parse_commit_in_graph(&r, c))
		die("Couldn't parse commit");
	tree = get_commit_tree_in_graph(&r, c);
	if (!tree)
		die("Couldn't get commit tree");

	printf("%s\n", oid_to_hex(&tree->object.oid));

	repo_clear(&r);
}

/* Keep one repository instance stale while a second writer settles it. */
static int test_settle_object_format(int argc, const char **argv)
{
	struct repository r, other;
	struct object_id oid;
	int algo, ret;

	if (argc < 4 || argc > 5)
		die("usage: repository settle-object-format <gitdir> <hash> [<competing-hash>]");
	algo = hash_algo_by_name(argv[3]);
	if (!algo || repo_init(&r, argv[2], NULL))
		die("cannot initialize repository");
	/* Exercise refresh of a backend opened before the competing write. */
	get_main_ref_store(&r);
	if (argc == 5) {
		struct child_process cmd = CHILD_PROCESS_INIT;
		struct strbuf output = STRBUF_INIT;
		int competing = hash_algo_by_name(argv[4]);
		if (!competing || repo_init(&other, argv[2], NULL) ||
		    repo_settle_object_format(&other, &hash_algos[competing]))
			die("competing writer failed");
		repo_clear(&other);
		cmd.git_cmd = 1;
		strvec_pushl(&cmd.args, "--git-dir", argv[2], "hash-object", "-w", "--stdin", NULL);
		if (pipe_command(&cmd, "winner", 6, &output, 0, NULL, 0) ||
		    get_oid_hex_algop(output.buf, &oid, &hash_algos[competing]))
			die("cannot write object");
		strbuf_release(&output);
		child_process_init(&cmd);
		cmd.git_cmd = 1;
		strvec_pushl(&cmd.args, "--git-dir", argv[2], "update-ref",
			      "refs/winner", oid_to_hex(&oid), NULL);
		if (run_command(&cmd))
			die("cannot write ref");
	}
	ret = repo_settle_object_format(&r, &hash_algos[algo]);
	if (!ret && argc == 5) {
		struct object_id actual;
		if (refs_read_ref(get_main_ref_store(&r), "refs/winner", &actual) ||
		    !oideq(&actual, &oid))
			die("stale ref backend after settlement");
	}
	repo_clear(&r);
	return !!ret;
}

/* Simulate interruption after replacing reftables but before updating config. */
static int test_rewrite_object_format(int argc, const char **argv)
{
	struct repository r;
	struct lock_file lock = LOCK_INIT;
	struct strbuf config = STRBUF_INIT;
	int algo, ret;

	if (argc != 4)
		die("usage: repository rewrite-object-format <gitdir> <hash>");
	algo = hash_algo_by_name(argv[3]);
	if (!algo || repo_init(&r, argv[2], NULL) || !r.provisional_object_formats.nr)
		die("expected a repository with provisional object formats");
	repo_common_path_append(&r, &config, "config");
	hold_lock_file_for_update(&lock, config.buf, LOCK_DIE_ON_ERROR);
	ret = refs_set_object_format(get_main_ref_store(&r), &hash_algos[algo], 1);
	rollback_lock_file(&lock);
	strbuf_release(&config);
	repo_clear(&r);
	return !!ret;
}

int cmd__repository(int argc, const char **argv)
{
	if (argc < 2)
		die("must have at least 2 arguments");
	if (!strcmp(argv[1], "settle-object-format")) {
		return test_settle_object_format(argc, argv);
	} else if (!strcmp(argv[1], "rewrite-object-format")) {
		return test_rewrite_object_format(argc, argv);
	} else if (!strcmp(argv[1], "parse_commit_in_graph")) {
		struct object_id oid;
		if (argc < 5)
			die("not enough arguments");
		if (parse_oid_hex_any(argv[4], &oid, &argv[4]) == GIT_HASH_UNKNOWN)
			die("cannot parse oid '%s'", argv[4]);
		test_parse_commit_in_graph(argv[2], argv[3], &oid);
	} else if (!strcmp(argv[1], "get_commit_tree_in_graph")) {
		struct object_id oid;
		if (argc < 5)
			die("not enough arguments");
		if (parse_oid_hex_any(argv[4], &oid, &argv[4]) == GIT_HASH_UNKNOWN)
			die("cannot parse oid '%s'", argv[4]);
		test_get_commit_tree_in_graph(argv[2], argv[3], &oid);
	} else {
		die("unrecognized '%s'", argv[1]);
	}
	return 0;
}
