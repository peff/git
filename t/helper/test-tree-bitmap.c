#include "cache.h"
#include "revision.h"
#include "diffcore.h"
#include "argv-array.h"
#include "ewah/ewok.h"
#include "varint.h"

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

	/* dump it while we have the sorted order in memory */
	for (i = 0; i < n; i++) {
		printf("%s", sorted[i]->path);
		putchar('\0');
	}
	putchar('\0');

	free(sorted);
}

static void strbuf_add_varint(struct strbuf *out, uintmax_t val)
{
	size_t len;
	strbuf_grow(out, 16); /* enough for any varint */
	len = encode_varint(val, (unsigned char *)out->buf + out->len);
	strbuf_setlen(out, out->len + len);
}

static void bitmap_to_rle(struct strbuf *out, struct bitmap *bitmap)
{
	int curval = 0; /* count zeroes, then ones, then zeroes, etc */
	size_t run = 0;
	size_t word;
	size_t orig_len = out->len;

	for (word = 0; word < bitmap->word_alloc; word++) {
		int bit;

		for (bit = 0; bit < BITS_IN_EWORD; bit++) {
			int val = !!(bitmap->words[word] & (((eword_t)1) << bit));
			if (val == curval)
				run++;
			else {
				strbuf_add_varint(out, run);
				curval = 1 - curval; /* flip 0/1 */
				run = 1;
			}
		}
	}

	/*
	 * complete the run, but do not bother with trailing zeroes, unless we
	 * failed to write even an initial run of 0's.
	 */
	if (curval && run)
		strbuf_add_varint(out, run);
	else if (orig_len == out->len)
		strbuf_add_varint(out, 0);

	/* signal end-of-input with an empty run */
	strbuf_add_varint(out, 0);
}

/* generate the bitmap for a single commit */
static void generate_bitmap(struct diff_queue_struct *q,
			    struct diff_options *opts,
			    void *vdata)
{
	struct walk_paths_data *data = vdata;
	struct bitmap *bitmap = bitmap_new();
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

	bitmap_to_rle(&out, bitmap);

	fwrite(data->commit->object.oid.hash, 1, GIT_SHA1_RAWSZ, stdout);
	fwrite(out.buf, 1, out.len, stdout);

	trace_printf("bitmap %s %u %u",
		     oid_to_hex(&data->commit->object.oid),
		     (unsigned)q->nr,
		     (unsigned)out.len);

	strbuf_release(&out);
	bitmap_free(bitmap);
}

static void do_gen(void)
{
	struct hashmap paths;
	setup_git_directory();
	collect_paths(&paths);

	walk_paths(generate_bitmap, &paths);
}

static void show_path(size_t pos, void *data)
{
	const char **paths = data;

	/* assert(pos < nr_paths), but we didn't pass the latter in */
	printf("%s\n", paths[pos]);
}

static size_t rle_each_bit(const unsigned char *in, size_t len,
			   void (*fn)(size_t, void *), void *data)
{
	int curval = 0; /* look for zeroes first, then ones, etc */
	const unsigned char *cur = in;
	const unsigned char *end = in + len;
	size_t pos;

	/* we always have a first run, even if it's 0 zeroes */
	pos = decode_varint(&cur);

	/*
	 * ugh, varint does not seem to have a way to prevent reading past
	 * the end of the buffer. We'll do a length check after each one,
	 * so the worst case is bounded.
	 */
	if (cur > end) {
		error("input underflow in rle");
		return len;
	}

	while (1) {
		size_t run = decode_varint(&cur);

		if (cur > end) {
			error("input underflow in rle");
			return len;
		}

		if (!run)
			break; /* empty run signals end */

		curval = 1 - curval; /* flip 0/1 */
		if (curval) {
			/* we have a run of 1's; deliver them */
			size_t i;
			for (i = 0; i < run; i++)
				fn(pos + i, data);
		}
		pos += run;
	}

	return cur - in;
}

static void do_dump(void)
{
	struct strbuf in = STRBUF_INIT;
	const char *cur;
	size_t remain;

	const char **paths = NULL;
	size_t alloc_paths = 0, nr_paths = 0;

	/* slurp stdin; in the real world we'd mmap all this */
	strbuf_read(&in, 0, 0);
	cur = in.buf;
	remain = in.len;

	/* read path for each bit; in the real world this would be separate */
	while (remain) {
		const char *end = memchr(cur, '\0', remain);
		if (!end) {
			error("truncated input while reading path");
			goto out;
		}
		if (end == cur) {
			/* empty field signals end of paths */
			cur++;
			remain--;
			break;
		}

		ALLOC_GROW(paths, nr_paths + 1, alloc_paths);
		paths[nr_paths++] = cur;

		remain -= end - cur + 1;
		cur = end + 1;
	}

	/* read the bitmap for each commit */
	while (remain) {
		struct object_id oid;
		ssize_t len;

		if (remain < GIT_SHA1_RAWSZ) {
			error("truncated input reading oid");
			goto out;
		}
		hashcpy(oid.hash, (const unsigned char *)cur);
		cur += GIT_SHA1_RAWSZ;
		remain -= GIT_SHA1_RAWSZ;

		printf("%s\n", oid_to_hex(&oid));
		len = rle_each_bit((const unsigned char *)cur, remain, show_path, paths);

		cur += len;
		remain -= len;
	}

out:
	free(paths);
	strbuf_release(&in);
}

int cmd_main(int argc, const char **argv)
{
	const char *usage_msg = "test-tree-bitmap <gen|dump>";

	if (!argv[1])
		usage(usage_msg);
	else if (!strcmp(argv[1], "gen"))
		do_gen();
	else if (!strcmp(argv[1], "dump"))
		do_dump();
	else
		usage(usage_msg);

	return 0;
}
