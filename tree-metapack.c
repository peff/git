#include "cache.h"
#include "tree-metapack.h"
#include "metapack.h"
#include "commit.h"
#include "diff.h"
#include "diffcore.h"

struct tree_metapack {
	struct metapack mp;
	struct packed_git *pack;
	uint32_t nr;
	const unsigned char *index;

	struct tree_metapack *next;
} *tree_metapacks;

static struct tree_metapack *alloc_tree_metapack(struct packed_git *pack)
{
	struct tree_metapack *it = xcalloc(1, sizeof(*it));
	uint32_t version;
	const unsigned char *data;
	off_t len;

	if (metapack_init(&it->mp, pack, "trees", &version) < 0) {
		free(it);
		return NULL;
	}
	if (version != 1) {
		metapack_close(&it->mp);
		free(it);
		return NULL;
	}

	data = it->mp.data;
	len = it->mp.len;
#define NEED(n) do { \
	if (len < (n)) { \
		warning("tree metapack for '%s' is truncated", pack->pack_name); \
		metapack_close(&it->mp); \
		free(it); \
		return NULL; \
	} \
} while(0)
#define DONE(n) do { \
	data += (n); \
	len -= (n); \
} while(0)
#define USE(n) do { NEED(n); DONE(n); } while(0)

	NEED(4);
	it->nr = get_be32(data);
	DONE(4);

	it->index = data;
	USE((off_t)it->nr * 4);

#undef USE
#undef DONE
#undef NEED

	it->pack = pack;

	return it;
}

static void prepare_tree_metapacks(void)
{
	static int initialized;
	struct tree_metapack **tail = &tree_metapacks;
	struct packed_git *p;

	if (initialized)
		return;

	prepare_packed_git();
	for (p = packed_git; p; p = p->next) {
		struct tree_metapack *it = alloc_tree_metapack(p);

		if (it) {
			*tail = it;
			tail = &it->next;
		}
	}

	initialized = 1;
}

/* XXX find_object_entry_pos uses ints to return 32-bit offsets! */
static int sha1_to_uint32(const unsigned char *sha1, struct packed_git *p,
			  uint32_t *pos)
{
	int r;

	if (is_null_sha1(sha1)) {
		*pos = 0xffffffff;
		return 0;
	}

	r = find_pack_entry_pos(sha1, p);
	if (r == -1)
		return -1;
	*pos = r;
	return 0;
}

static const unsigned char *uint32_to_sha1(struct packed_git *pack, uint32_t pos)
{
	if (pos == 0xffffffff)
		return null_sha1;
	return nth_packed_object_sha1(pack, pos);
}

static int emit_tree_metapack(struct tree_metapack *p,
			      uint32_t pos,
			      tree_metapack_fun cb,
			      void *data)
{
	const unsigned char *base = p->mp.data + pos;
	/* XXX account for size of record itself; there
	 * should probably be a better fill/use cursor
	 * pattern */
	while (base < p->mp.data + p->mp.len) {
		uint32_t path_pos = get_be32(base);
		unsigned old_mode, new_mode;
		uint32_t old_sha1_pos, new_sha1_pos;

		if (!path_pos)
			return 0;

		base += 4;
		old_mode = get_be16(base);
		base += 2;
		new_mode = get_be16(base);
		base += 2;

		old_sha1_pos = get_be32(base);
		base += 4;
		new_sha1_pos = get_be32(base);
		base += 4;

		cb((const char *)(p->mp.data + path_pos),
		   old_mode, new_mode,
		   uint32_to_sha1(p->pack, old_sha1_pos),
		   uint32_to_sha1(p->pack, new_sha1_pos),
		   data);
	}
	warning("truncated tree metapack");
	return -1;
}

static int lookup_tree_metapack(struct tree_metapack *p,
				const unsigned char *sha1,
				const unsigned char *parent,
				tree_metapack_fun cb,
				void *data)
{
	uint32_t lo, hi;

	lo = 0;
	hi = p->nr;
	while (lo < hi) {
		uint32_t mi = lo + (hi - lo) / 2;
		const unsigned char *base = p->index + (size_t)mi * 12;
		uint32_t commit = get_be32(base);
		int cmp = hashcmp(sha1, uint32_to_sha1(p->pack, commit));

		if (!cmp) {
			uint32_t parent_pos = get_be32(base + 4);
			uint32_t diff_pos = get_be32(base + 8);
			if (hashcmp(parent, uint32_to_sha1(p->pack, parent_pos))) {
				return -1;
			}
			return emit_tree_metapack(p, diff_pos, cb, data);
		}

		if (cmp < 0)
			hi = mi;
		else
			lo = mi + 1;
	}
	return -1;
}

int tree_metapack(const unsigned char *sha1,
		  const unsigned char *parent,
		  tree_metapack_fun cb,
		  void *data)
{
	struct tree_metapack *p;

	prepare_tree_metapacks();
	for (p = tree_metapacks; p; p = p->next) {
		if (!lookup_tree_metapack(p, sha1, parent, cb, data))
			return 0;
	}
	return -1;
}

struct path_entry {
	struct hashmap_entry ent;
	uint32_t offset;
	char name[FLEX_ARRAY];
};

struct diff_entry {
	uint32_t tree;
	uint32_t parent;
	struct pair_entry {
		struct path_entry *name;
		unsigned old_mode, new_mode;
		uint32_t old_sha1, new_sha1;
	} *paths;
	size_t nr;
};

struct write_cb {
	struct diff_options diffopt;
	struct hashmap paths;

	struct diff_entry *entries;
	size_t nr, alloc;
};

static void get_diffs(struct metapack_writer *mw,
		      const unsigned char *sha1,
		      void *vdata)
{
	struct write_cb *data = vdata;
	struct diff_entry *diff;
	struct commit *c;
	int i;
	enum object_type type = sha1_object_info(sha1, NULL);

	if (type != OBJ_COMMIT)
		return;

	c = lookup_commit(sha1);
	if (!c || parse_commit(c))
		die("unable to read commit %s", sha1_to_hex(sha1));
	if (!c->parents)
		return;
	/* XXX we should be able to store multiple parents */
	if (c->parents->next)
		return;
	if (parse_commit(c->parents->item))
		return;

	ALLOC_GROW(data->entries, data->nr + 1, data->alloc);
	diff = &data->entries[data->nr];

	if (sha1_to_uint32(c->tree->object.oid.hash, mw->pack, &diff->tree) < 0)
		return;
	if (sha1_to_uint32(c->parents->item->tree->object.oid.hash, mw->pack, &diff->parent) < 0)
		return;
	if (diff_tree_sha1(c->parents->item->tree->object.oid.hash,
			   c->tree->object.oid.hash,
			   "", &data->diffopt) < 0)
		return;

	diff->nr = diff_queued_diff.nr;
	diff->paths = xmalloc(diff->nr * sizeof(*diff->paths));
	for (i = 0; i < diff->nr; i++) {
		struct diff_filepair *p = diff_queued_diff.queue[i];
		struct diff_filespec *old = p->one, *new = p->two;
		struct pair_entry *out = &diff->paths[i];

		if (sha1_to_uint32(old->sha1, mw->pack, &out->old_sha1) < 0 ||
		    sha1_to_uint32(new->sha1, mw->pack, &out->new_sha1) < 0) {
			free(diff->paths);
			diff_flush(&data->diffopt);
			return;
		}

		out->old_mode = old->mode;
		out->new_mode = new->mode;

		out->name = hashmap_get_from_hash(&data->paths,
						  strhash(old->path),
						  old->path);
		if (!out->name) {
			size_t len = strlen(old->path) + 1;
			out->name = xmalloc(sizeof(*out->name) + len);
			hashmap_entry_init(&out->name->ent, strhash(old->path));
			memcpy(out->name->name, old->path, len);
			hashmap_put(&data->paths, out->name);
		}
	}

	diff_flush(&data->diffopt);
	data->nr++;
}

static int path_entry_cmp(const void *va, const void *vb)
{
	const struct path_entry * const *a = va;
	const struct path_entry * const *b = vb;
	return strcmp((*a)->name, (*b)->name);
}

static struct path_entry **sort_paths(struct hashmap *paths, uint32_t offset)
{
	struct hashmap_iter iter;
	struct path_entry *p;
	struct path_entry **sorted;
	int i;

	sorted = xmalloc(paths->size * sizeof(*sorted));

	for (i = 0, p = hashmap_iter_first(paths, &iter); p; p = hashmap_iter_next(&iter), i++)
		sorted[i] = p;
	qsort(sorted, paths->size, sizeof(*sorted), path_entry_cmp);

	for (i = 0; i < paths->size; i++) {
		sorted[i]->offset = offset;
		offset += strlen(sorted[i]->name) + 1;
	}

	return sorted;
}

static int path_entry_hashcmp(const struct path_entry *e1,
			       const struct path_entry *e2,
			       const char *key)
{
	return strcmp(e1->name, key ? key : e2->name);
}

static int diff_entry_cmp(const void *va, const void *vb, void *data)
{
	const struct diff_entry *a = va, *b = vb;
	return hashcmp(uint32_to_sha1(data, a->tree),
		       uint32_to_sha1(data, b->tree));
}

void tree_metapack_write(const char *idx)
{
	struct metapack_writer mw;
	struct write_cb data;
	uint32_t i;
	uint32_t offset;
	struct path_entry **paths;

	metapack_writer_init(&mw, idx, "trees", 1);

	/* Figure out how many eligible commits we've got in this pack. */
	memset(&data, 0, sizeof(data));
	hashmap_init(&data.paths, (hashmap_cmp_fn)path_entry_hashcmp, 0);
	diff_setup(&data.diffopt);
	DIFF_OPT_SET(&data.diffopt, RECURSIVE);
	metapack_writer_foreach(&mw, get_diffs, &data);
	metapack_writer_add_uint32(&mw, data.nr);

	qsort_r(data.entries, data.nr, sizeof(*data.entries),
		diff_entry_cmp, mw.pack);

	/* Then write an index entry for each commit */
	offset = 4 + 12 * data.nr; /* offset of diff start */
	for (i = 0; i < data.nr; i++) {
		struct diff_entry *d = &data.entries[i];
		metapack_writer_add_uint32(&mw, d->tree);
		metapack_writer_add_uint32(&mw, d->parent);
		metapack_writer_add_uint32(&mw, offset);
		offset += 4 + 16 * d->nr;
	}

	paths = sort_paths(&data.paths, offset);

	/* Now the actual diff entries. */
	for (i = 0; i < data.nr; i++) {
		struct diff_entry *d = &data.entries[i];
		int j;
		for (j = 0; j < d->nr; j++) {
			struct pair_entry *p = &d->paths[j];
			metapack_writer_add_uint32(&mw, p->name->offset);
			metapack_writer_add_uint16(&mw, p->old_mode);
			metapack_writer_add_uint16(&mw, p->new_mode);
			metapack_writer_add_uint32(&mw, p->old_sha1);
			metapack_writer_add_uint32(&mw, p->new_sha1);
		}
		metapack_writer_add_uint32(&mw, 0);
	}

	/* And then the paths */
	for (i = 0; i < data.paths.size; i++) {
		const char *name = paths[i]->name;
		metapack_writer_add(&mw, name, strlen(name) + 1);
	}

	metapack_writer_finish(&mw);
	for (i = 0; i < data.nr; i++)
		free(data.entries[i].paths);
	free(data.entries);
}
