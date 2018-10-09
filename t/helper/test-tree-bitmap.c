#include "cache.h"
#include "revision.h"
#include "diffcore.h"
#include "argv-array.h"
#include "ewah/ewok.h"

/* map of pathnames to bit positions */
struct pathmap_entry {
	struct hashmap_entry ent;
	unsigned pos;
	char path[FLEX_ARRAY];
};

static int pathmap_entry_hashcmp(const void *unused_cmp_data,
				 const void *entry,
				 const void *entry_or_key,
				 const void *keydata)
{
	const struct pathmap_entry *a = entry;
	const struct pathmap_entry *b = entry_or_key;
	const char *key = keydata;

	return strcmp(a->path, key ? key : b->path);
}

static int pathmap_entry_strcmp(const void *va, const void *vb)
{
	struct pathmap_entry *a = *(struct pathmap_entry **)va;
	struct pathmap_entry *b = *(struct pathmap_entry **)vb;
	return strcmp(a->path, b->path);
}

struct walk_paths_data {
	struct hashmap *paths;
	struct commit *commit;
};

static void walk_paths(diff_format_fn_t fn, struct hashmap *paths)
{
	struct argv_array argv = ARGV_ARRAY_INIT;
	struct rev_info revs;
	struct walk_paths_data data;
	struct commit *commit;

	argv_array_pushl(&argv, "rev-list",
			 "--all", "-t", "--no-renames",
			 NULL);
	init_revisions(&revs, NULL);
	setup_revisions(argv.argc, argv.argv, &revs, NULL);
	revs.diffopt.output_format = DIFF_FORMAT_CALLBACK;
	revs.diffopt.format_callback = fn;
	revs.diffopt.format_callback_data = &data;

	data.paths = paths;

	prepare_revision_walk(&revs);
	while ((commit = get_revision(&revs))) {
		data.commit = commit;
		diff_tree_combined_merge(commit, 0, &revs);
	}

	reset_revision_walk();
	argv_array_clear(&argv);
}

static void collect_commit_paths(struct diff_queue_struct *q,
				 struct diff_options *opts,
				 void *vdata)
{
	struct walk_paths_data *data = vdata;
	int i;

	for (i = 0; i < q->nr; i++) {
		struct diff_filepair *p = q->queue[i];
		const char *path = p->one->path;
		struct pathmap_entry *entry;
		struct hashmap_entry lookup;

		hashmap_entry_init(&lookup, strhash(path));
		entry = hashmap_get(data->paths, &lookup, path);
		if (entry)
			continue; /* already present */

		FLEX_ALLOC_STR(entry, path, path);
		entry->ent = lookup;
		hashmap_put(data->paths, entry);
	}
}

/* assign a bit position to all possible paths */
static void collect_paths(struct hashmap *paths)
{
	struct pathmap_entry **sorted;
	size_t i, n;
	struct hashmap_iter iter;
	struct pathmap_entry *entry;

	/* grab all unique paths */
	hashmap_init(paths, pathmap_entry_hashcmp, NULL, 0);
	walk_paths(collect_commit_paths, paths);

	/* and assign them bits in sorted order */
	n = hashmap_get_size(paths);
	ALLOC_ARRAY(sorted, n);
	i = 0;
	for (entry = hashmap_iter_first(paths, &iter);
	     entry;
	     entry = hashmap_iter_next(&iter)) {
		assert(i < n);
		sorted[i++] = entry;
	}
	QSORT(sorted, i, pathmap_entry_strcmp);
	for (i = 0; i < n; i++)
		sorted[i]->pos = i;
	free(sorted);
}

/* generate the bitmap for a single commit */
static void generate_bitmap(struct diff_queue_struct *q,
			    struct diff_options *opts,
			    void *vdata)
{
	struct walk_paths_data *data = vdata;
	struct bitmap *bitmap = bitmap_new();
	struct ewah_bitmap *ewah;
	struct strbuf out = STRBUF_INIT;
	size_t i;

	for (i = 0; i < q->nr; i++) {
		struct diff_filepair *p = q->queue[i];
		const char *path = p->one->path;
		struct pathmap_entry *entry;
		struct hashmap_entry lookup;

		hashmap_entry_init(&lookup, strhash(path));
		entry = hashmap_get(data->paths, &lookup, path);
		if (!entry)
			BUG("mysterious path appeared: %s", path);

		bitmap_set(bitmap, entry->pos);
	}

	ewah = bitmap_to_ewah(bitmap);
	ewah_serialize_strbuf(ewah, &out);
	fwrite(out.buf, 1, out.len, stdout);

	trace_printf("bitmap %s %u %u",
		     oid_to_hex(&data->commit->object.oid),
		     (unsigned)q->nr,
		     (unsigned)out.len);

	strbuf_release(&out);
	ewah_free(ewah);
	bitmap_free(bitmap);
}

int cmd_main(int argc, const char **argv)
{
	struct hashmap paths;

	setup_git_directory();
	collect_paths(&paths);

	walk_paths(generate_bitmap, &paths);

	return 0;
}
