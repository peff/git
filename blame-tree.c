#include "cache.h"
#include "blame-tree.h"
#include "commit.h"
#include "diff.h"
#include "diffcore.h"
#include "revision.h"
#include "log-tree.h"

static int add_path(const unsigned char *sha1, struct strbuf *base,
		    const char *name, unsigned mode, int stage, void *data)
{
	struct blame_tree *bt = data;
	int recursive = DIFF_OPT_TST(&bt->rev.diffopt, RECURSIVE);
	int show_tree = DIFF_OPT_TST(&bt->rev.diffopt, TREE_IN_RECURSIVE);

	if (!S_ISDIR(mode) || !recursive || show_tree) {
		size_t orig_len = base->len;
		struct string_list_item *item;
		struct blame_tree_entry *e;

		strbuf_addstr(base, name);
		item = string_list_append(&bt->paths, base->buf);
		FLEX_ALLOC_STR(e, name, base->buf);
		item->util = e;
		strbuf_setlen(base, orig_len);
	}

	return recursive ? READ_TREE_RECURSIVE : 0;
}

static int add_from_tree(struct blame_tree *bt, struct tree *tree)
{
	if (read_tree_recursive(tree, "", 0, 0, &bt->rev.prune_data, add_path, bt) < 0)
		return error("unable to read tree object");
	return 0;
}

static int add_from_revs(struct blame_tree *bt)
{
	unsigned int i;

	for (i = 0; i < bt->rev.pending.nr; i++) {
		struct object_array_entry *obj = bt->rev.pending.objects + i;
		struct tree *tree = parse_tree_indirect(obj->item->oid.hash);

		if (!tree)
			return error("not a tree: %s", obj->name);

		if (add_from_tree(bt, tree) < 0)
			return -1;
	}

	string_list_sort(&bt->paths);
	return 0;
}

void blame_tree_init(struct blame_tree *bt, int argc, const char **argv)
{
	memset(bt, 0, sizeof(*bt));
	bt->paths.strdup_strings = 1;

	init_revisions(&bt->rev, NULL);
	bt->rev.def = "HEAD";
	bt->rev.combine_merges = 1;
	setup_revisions(argc, argv, &bt->rev, NULL);

	if (add_from_revs(bt) < 0)
		die("unable to setup blame-tree");
}

void blame_tree_release(struct blame_tree *bt)
{
	string_list_clear(&bt->paths, 0);
}

struct blame_tree_callback_data {
	struct commit *commit;
	struct string_list *paths;
	int num_interesting;

	blame_tree_callback callback;
	void *callback_data;
};

static void mark_path(const char *path, struct blame_tree_callback_data *data)
{
	struct string_list_item *item = string_list_lookup(data->paths, path);
	struct blame_tree_entry *e;

	if (!item || !item->util)
		return;
	e = item->util;

	if (e->commit)
		return;

	e->commit = data->commit;
	data->num_interesting--;
	if (data->callback)
		data->callback(e->name, path, e->commit, data->callback_data);
}

static void rename_path(const char *from, const char *to,
			struct blame_tree_callback_data *data)
{
	struct string_list_item *old_item = string_list_lookup(data->paths, to);
	struct string_list_item *new_item;
	struct blame_tree_entry *e;

	if (!old_item || !old_item->util)
		return;
	e = old_item->util;

	if (e->commit)
		return;

	new_item = string_list_insert(data->paths, from);
	new_item->util = old_item->util;
	old_item->util = NULL;
}

static void process_diff(struct diff_queue_struct *q,
			 struct diff_options *opt, void *cbdata)
{
	struct blame_tree_callback_data *data = cbdata;
	int i;

	for (i = 0; i < q->nr; i++) {
		struct diff_filepair *p = q->queue[i];
		switch (p->status) {
		case DIFF_STATUS_RENAMED:
			mark_path(p->one->path, data);
			if (p->score == (int)MAX_SCORE)
				rename_path(p->one->path, p->two->path, data);
			else
				mark_path(p->two->path, data);
			break;
		case DIFF_STATUS_COPIED:
			if (p->score == (int)MAX_SCORE)
				rename_path(p->one->path, p->two->path, data);
			else
				mark_path(p->two->path, data);
			break;
		case DIFF_STATUS_ADDED:
			mark_path(p->two->path, data);
			break;
		case DIFF_STATUS_DELETED:
			mark_path(p->one->path, data);
			break;
		default:
			mark_path(p->one->path, data);
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

	bt->rev.no_commit_id = 1;
	bt->rev.diff = 1;
	bt->rev.diffopt.output_format = DIFF_FORMAT_CALLBACK;
	bt->rev.diffopt.format_callback = process_diff;
	bt->rev.diffopt.format_callback_data = &data;
	diff_setup_done(&bt->rev.diffopt);

	prepare_revision_walk(&bt->rev);

	while (data.num_interesting > 0) {
		data.commit = get_revision(&bt->rev);
		if (!data.commit)
			break;

		log_tree_commit(&bt->rev, data.commit);
	}
	return 0;
}
