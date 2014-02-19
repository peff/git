#include "cache.h"
#include "blame-tree.h"
#include "commit.h"
#include "diff.h"
#include "diffcore.h"
#include "revision.h"
#include "log-tree.h"
#include "dir.h"
#include "argv-array.h"

struct blame_tree_entry {
	struct object_id oid;
	struct commit *commit;
};

static void add_from_diff(struct diff_queue_struct *q,
			  struct diff_options *opt,
			  void *data)
{
	struct blame_tree *bt = data;
	int i;

	for (i = 0; i < q->nr; i++) {
		struct diff_filepair *p = q->queue[i];
		struct blame_tree_entry *ent = xcalloc(1, sizeof(*ent));
		struct string_list_item *it;

		oidcpy(&ent->oid, &p->two->oid);
		it = string_list_append(&bt->paths, p->two->path);
		it->util = ent;
	}
}

static int add_from_revs(struct blame_tree *bt)
{
	unsigned int i;
	int count = 0;
	struct diff_options diffopt;

	memcpy(&diffopt, &bt->rev.diffopt, sizeof(diffopt));
	diffopt.output_format = DIFF_FORMAT_CALLBACK;
	diffopt.format_callback = add_from_diff;
	diffopt.format_callback_data = bt;

	for (i = 0; i < bt->rev.pending.nr; i++) {
		struct object_array_entry *obj = bt->rev.pending.objects + i;

		if (obj->item->flags & UNINTERESTING)
			continue;

		if (count++)
			return error("can only blame one tree at a time");

		diff_tree_oid(&empty_tree_oid, &obj->item->oid, "", &diffopt);
		diff_flush(&diffopt);
	}

	string_list_sort(&bt->paths);
	return 0;
}

static void setup_pathspec(struct pathspec *ps,
			   const struct string_list *paths)
{
	struct argv_array argv = ARGV_ARRAY_INIT;
	int i;

	for (i = 0; i < paths->nr; i++)
		argv_array_push(&argv, paths->items[i].string);

	clear_pathspec(ps);
	parse_pathspec(ps, PATHSPEC_ALL_MAGIC & ~PATHSPEC_LITERAL,
		       PATHSPEC_PREFER_FULL | PATHSPEC_LITERAL_PATH, "",
		       argv.argv);
}

static void drop_pathspec_from_trie(struct pathspec *ps,
				    const char *path)
{
	struct pathspec_trie *prev, *cur = ps->trie;
	int pos = -1;

	if (!cur)
		return;

	while (*path) {
		const char *end = strchrnul(path, '/');
		size_t len = end - path;
		pos = pathspec_trie_lookup(cur, path, len);

		if (pos < 0)
			die("BUG: didn't find the pathspec trie we matched");

		prev = cur;
		cur = cur->entries[pos];
		path = end;
		while (*path == '/')
			path++;
	}

	if (!cur->terminal)
		die("BUG: pathspec trie we found isn't terminal?");

	if (cur->nr) {
		cur->terminal = 0;
		cur->must_be_dir = 0;
		return;
	}

	free(cur);
	if (pos < 0)
		ps->trie = NULL;
	else {
		prev->nr--;
		memmove(prev->entries + pos,
			prev->entries + pos + 1,
			sizeof(*prev->entries) * (prev->nr - pos));
	}
}

static void drop_pathspec(struct pathspec *ps, const char *path)
{
	int i;

	/* We know these are literals, so we can just strcmp */
	for (i = 0; i < ps->nr; i++)
		if (!strcmp(ps->items[i].match, path))
			break;

	if (i == ps->nr)
		die("BUG: didn't find the pathspec we just matched");

	memmove(ps->items + i, ps->items + i + 1,
		sizeof(*ps->items) * (ps->nr - i - 1));
	ps->nr--;

	drop_pathspec_from_trie(ps, path);
}

void blame_tree_init(struct blame_tree *bt, int argc, const char **argv,
		     const char *prefix)
{
	memset(bt, 0, sizeof(*bt));
	bt->paths.strdup_strings = 1;

	init_revisions(&bt->rev, prefix);
	bt->rev.def = "HEAD";
	bt->rev.combine_merges = 1;
	bt->rev.show_root_diff = 1;
	bt->rev.boundary = 1;
	bt->rev.no_commit_id = 1;
	bt->rev.diff = 1;
	DIFF_OPT_SET(&bt->rev.diffopt, RECURSIVE);
	setup_revisions(argc, argv, &bt->rev, NULL);

	if (add_from_revs(bt) < 0)
		die("unable to setup blame-tree");

	setup_pathspec(&bt->rev.prune_data, &bt->paths);
	copy_pathspec(&bt->rev.pruning.pathspec, &bt->rev.prune_data);
	copy_pathspec(&bt->rev.diffopt.pathspec, &bt->rev.prune_data);
	bt->rev.prune = 1;

	/*
	 * Have the diff engine tell us about everything, including trees.
	 * We may have used --max-depth to get our list of paths to blame,
	 * in which case we would mention trees explicitly.
	 */
	DIFF_OPT_SET(&bt->rev.diffopt, TREE_IN_RECURSIVE);
}

void blame_tree_release(struct blame_tree *bt)
{
	string_list_clear(&bt->paths, 1);
}


struct blame_tree_callback_data {
	struct commit *commit;
	struct string_list *paths;
	int num_interesting;
	struct rev_info *rev;

	blame_tree_callback callback;
	void *callback_data;
};

static void mark_path(const char *path, const struct object_id *oid,
		      struct blame_tree_callback_data *data)
{
	struct string_list_item *item = string_list_lookup(data->paths, path);
	struct blame_tree_entry *ent;

	/* Is it even a path that exists in our tree? */
	if (!item)
		return;

	/* Have we already blamed a commit? */
	ent = item->util;
	if (ent->commit)
		return;
	/*
	 * Is it arriving at a version of interest, or is it from a side branch
	 * which did not contribute to the final state?
	 */
	if (oidcmp(oid, &ent->oid))
		return;

	ent->commit = data->commit;
	data->num_interesting--;
	if (data->callback)
		data->callback(path, data->commit, data->callback_data);

	drop_pathspec(&data->rev->pruning.pathspec, path);
	clear_pathspec(&data->rev->diffopt.pathspec);
	copy_pathspec(&data->rev->diffopt.pathspec, &data->rev->pruning.pathspec);
}

static void blame_diff(struct diff_queue_struct *q,
			 struct diff_options *opt, void *cbdata)
{
	struct blame_tree_callback_data *data = cbdata;
	int i;

	for (i = 0; i < q->nr; i++) {
		struct diff_filepair *p = q->queue[i];
		switch (p->status) {
		case DIFF_STATUS_DELETED:
			/*
			 * There's no point in feeding a deletion, as it could
			 * not have resulted in our current state, which
			 * actually has the file.
			 */
			break;

		default:
			/*
			 * Otherwise, we care only that we somehow arrived at
			 * a final path/sha1 state. Note that this covers some
			 * potentially controversial areas, including:
			 *
			 *  1. A rename or copy will be blamed, as it is the
			 *     first time the content has arrived at the given
			 *     path.
			 *
			 *  2. Even a non-content modification like a mode or
			 *     type change will trigger it.
			 *
			 * We take the inclusive approach for now, and blame
			 * anything which impacts the path. Options to tweak
			 * the behavior (e.g., to "--follow" the content across
			 * renames) can come later.
			 */
			mark_path(p->two->path, &p->two->oid, data);
			break;
		}
	}
}

int blame_tree_run(struct blame_tree *bt, blame_tree_callback cb, void *cbdata)
{
	struct blame_tree_callback_data data;

	data.paths = &bt->paths;
	data.num_interesting = bt->paths.nr;
	data.callback = cb;
	data.callback_data = cbdata;
	data.rev = &bt->rev;

	bt->rev.diffopt.output_format = DIFF_FORMAT_CALLBACK;
	bt->rev.diffopt.format_callback = blame_diff;
	bt->rev.diffopt.format_callback_data = &data;

	prepare_revision_walk(&bt->rev);

	while (data.num_interesting > 0) {
		data.commit = get_revision(&bt->rev);
		if (!data.commit)
			break;

		if (data.commit->object.flags & BOUNDARY) {
			diff_tree_oid(&empty_tree_oid,
				      &data.commit->object.oid,
				      "", &bt->rev.diffopt);
			diff_flush(&bt->rev.diffopt);
		}
		else
			log_tree_commit(&bt->rev, data.commit);
	}

	return 0;
}
