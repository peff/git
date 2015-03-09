#include "cache.h"
#include "commit-metapack.h"
#include "metapack.h"
#include "commit.h"
#include "sha1-lookup.h"
#include "packfile.h"

struct commit_entry {
	uint32_t commit;	/* nth_packed_object_sha1 to get own SHA-1 */
	uint32_t timestamp;
	uint32_t tree;		/* nth_packed_object_sha1 to get tree SHA-1 */
	uint32_t parent1; /* nth_packed_object_sha1 to get 1st parent SHA-1 */
	uint32_t parent2; /* nth_packed_object_sha1 to get 2nd parent SHA-1 */
	uint32_t generation;
};

struct commit_metapack {
	struct metapack mp;
	uint32_t nr;
	struct packed_git *pack;
	unsigned char *index;
	unsigned char *data;
	struct commit_metapack *next;
};
static struct commit_metapack *commit_metapacks;

static struct commit_metapack *alloc_commit_metapack(struct packed_git *pack)
{
	struct commit_metapack *it = xcalloc(1, sizeof(*it));
	uint32_t version;

	if (metapack_init(&it->mp, pack, "commits", &version) < 0) {
		free(it);
		return NULL;
	}
	if (version != 1) {
		/*
		 * This file comes from a more recent git version. Don't bother
		 * warning the user, as we'll just fallback to reading the
		 * commits.
		 */
		metapack_close(&it->mp);
		free(it);
		return NULL;
	}

	if (it->mp.len < 4) {
		warning("commit metapack for '%s' is truncated", pack->pack_name);
		metapack_close(&it->mp);
		free(it);
		return NULL;
	}
	it->nr = get_be32(it->mp.data);
	it->index = it->mp.data + 4;
	it->data = it->index + 4 * it->nr;
	it->pack = pack;

	/*
	 * We need 20 bytes for each entry: commit index(4), date(4), tree
	 * index(4), parent indexes(8). Plus 4 bytes for the header.
	 */
	if (it->mp.len < 4 + it->nr * 24) {
		warning("commit metapack for '%s' is truncated", pack->pack_name);
		metapack_close(&it->mp);
		free(it);
		return NULL;
	}

	return it;
}

static void prepare_commit_metapacks(void)
{
	static int initialized;
	struct commit_metapack **tail = &commit_metapacks;
	struct packed_git *p;

	if (initialized)
		return;

	prepare_packed_git();
	for (p = packed_git; p; p = p->next) {
		struct commit_metapack *it = alloc_commit_metapack(p);

		if (it) {
			*tail = it;
			tail = &it->next;
		}
	}

	initialized = 1;
}

static int lookup_commit_metapack_one(struct commit_metapack *p,
				      const unsigned char *sha1,
				      struct commit_entry *out)
{
	uint32_t lo, hi;

	lo = 0;
	hi = p->nr;
	while (lo < hi) {
		uint32_t mi = lo + (hi - lo) / 2;
		const unsigned char *base = p->index + (size_t)mi * 4;
		uint32_t commit = get_be32(base);
		int cmp = hashcmp(sha1, nth_packed_object_sha1(p->pack, commit));

		if (!cmp) {
			base = p->data + (size_t)mi * 20;
			out->timestamp = get_be32(base);
			out->tree = get_be32(base+ 4);
			out->parent1 = get_be32(base + 8);
			out->parent2 = get_be32(base + 12);
			out->generation = get_be32(base + 16);
			return 0;
		}

		if (cmp < 0)
			hi = mi;
		else
			lo = mi + 1;
	}

	return -1;
}

int commit_metapack(const unsigned char *sha1,
		    uint32_t *timestamp,
		    uint32_t *generation,
		    const unsigned char **tree,
		    const unsigned char **parent1,
		    const unsigned char **parent2)
{
	struct commit_metapack *p;

	prepare_commit_metapacks();
	for (p = commit_metapacks; p; p = p->next) {
		struct commit_entry ent;
		if (!lookup_commit_metapack_one(p, sha1, &ent)) {
			*timestamp = ent.timestamp;
			*generation = ent.generation;
			*tree = nth_packed_object_sha1(p->pack, ent.tree);
			*parent1 = nth_packed_object_sha1(p->pack, ent.parent1);
			if (ent.parent1 != ent.parent2)
				*parent2 = nth_packed_object_sha1(p->pack, ent.parent2);
			else
				*parent2 = null_sha1;
			return 0;
		}
	}
	return -1;
}

struct write_cb {
	struct commit_entry *entries;
	uint32_t nr, alloc;
};

/* XXX find_object_entry_pos uses ints to return 32-bit offsets! */
static int find_obj(const struct object *obj, struct packed_git *p,
		    uint32_t *pos)
{
	int r = find_pack_entry_pos(obj->oid.hash, p);
	if (r == -1)
		return -1;
	*pos = r;
	return 0;
}

static void get_commits(struct metapack_writer *mw,
			const struct object_id *oid,
			void *vdata)
{
	struct write_cb *data = vdata;
	struct commit_entry *ent;
	struct commit *c;
	enum object_type type = sha1_object_info(oid->hash, NULL);

	if (type != OBJ_COMMIT)
		return;

	c = lookup_commit(oid);
	if (!c || parse_commit(c))
		die("unable to read commit %s", oid_to_hex(oid));

	/*
	 * Our fixed-size parent list cannot represent root commits, nor
	 * octopus merges. Just skip those commits, as we can fallback
	 * in those rare cases to reading the actual commit object.
	 */
	if (!c->parents || (c->parents->next && c->parents->next->next))
		return;

	ALLOC_GROW(data->entries, data->nr + 1, data->alloc);
	ent = &data->entries[data->nr];

	find_obj(&c->object, mw->pack, &ent->commit);
	ent->timestamp = c->date;

	if (find_obj(&c->tree->object, mw->pack, &ent->tree))
		return;
	if (find_obj(&c->parents->item->object, mw->pack, &ent->parent1))
		return;
	if (!c->parents->next)
		ent->parent2 = ent->parent1;
	else {
		if (find_obj(&c->parents->next->item->object, mw->pack,
			     &ent->parent2))
			return;
	}
	ent->generation = commit_generation(c);

	data->nr++;
}

void commit_metapack_write(const char *idx)
{
	struct metapack_writer mw;
	struct write_cb data;
	uint32_t i;

	metapack_writer_init(&mw, idx, "commits", 1);

	/* Figure out how many eligible commits we've got in this pack. */
	memset(&data, 0, sizeof(data));
	metapack_writer_foreach(&mw, get_commits, &data);
	metapack_writer_add_uint32(&mw, data.nr);

	/* Then write an index of commit sha1s */
	for (i = 0; i < data.nr; i++)
		metapack_writer_add_uint32(&mw, data.entries[i].commit);

	for (i = 0; i < data.nr; i++) {
		struct commit_entry *ent = &data.entries[i];
		metapack_writer_add_uint32(&mw, ent->timestamp);
		metapack_writer_add_uint32(&mw, ent->tree);
		metapack_writer_add_uint32(&mw, ent->parent1);
		metapack_writer_add_uint32(&mw, ent->parent2);
		metapack_writer_add_uint32(&mw, ent->generation);
	}

	metapack_writer_finish(&mw);
	free(data.entries);
}
