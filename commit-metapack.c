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
};

struct commit_metapack {
	struct metapack mp;
	uint32_t nr;
	uint32_t abbrev_len;
	struct packed_git *pack;
	unsigned char *index;
	struct commit_entry *data;
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
	memcpy(&it->nr, it->mp.data, 4);
	it->nr = ntohl(it->nr);
	memcpy(&it->abbrev_len, it->mp.data + 4, 4);
	it->abbrev_len = ntohl(it->abbrev_len);
	it->pack = pack;

	/*
	 * We need 20+abbrev_len bytes for each entry: abbrev sha-1,
	 * date(4), tree index(4), parent indexes(8).
	 */
	if (it->mp.len < ((sizeof(*it->data) + it->abbrev_len) * it->nr + 8)) {
		warning("commit metapack for '%s' is truncated", pack->pack_name);
		metapack_close(&it->mp);
		free(it);
		return NULL;
	}

	it->index = it->mp.data + 8;
	it->data = (struct commit_entry*)(it->index + it->abbrev_len * it->nr);

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

int commit_metapack(const unsigned char *sha1,
		    uint32_t *timestamp,
		    const unsigned char **tree,
		    const unsigned char **parent1,
		    const unsigned char **parent2)
{
	struct commit_metapack *p;

	prepare_commit_metapacks();
	for (p = commit_metapacks; p; p = p->next) {
		struct commit_entry *data;
		uint32_t p1, p2;
		unsigned lo, hi;
		int pos;

		if (!p->nr)
			continue;

		/* sha1_entry_pos does not work with abbreviated sha-1 */
		lo = 0;
		hi = p->nr;
		pos = -1;
		do {
			unsigned mi = (lo + hi) / 2;
			int cmp = memcmp(p->index + mi * p->abbrev_len, sha1, p->abbrev_len);

			if (!cmp) {
				pos = mi;
				break;
			}
			if (cmp > 0)
				hi = mi;
			else
				lo = mi+1;
		} while (lo < hi);
		if (pos < 0)
			continue;

		data = p->data + pos;

		/* full sha-1 check again */
		if (hashcmp(nth_packed_object_sha1(p->pack,
						   ntohl(data->commit)), sha1))
			continue;

		*timestamp = ntohl(data->timestamp);
		*tree = nth_packed_object_sha1(p->pack, ntohl(data->tree));
		p1 = ntohl(data->parent1);
		*parent1 = nth_packed_object_sha1(p->pack, p1);
		p2 = ntohl(data->parent2);
		*parent2 = p1 == p2 ? null_sha1 : nth_packed_object_sha1(p->pack, p2);

		return 0;
	}

	return -1;
}

struct write_cb {
	struct commit_list **tail;
	int abbrev_len;
	const unsigned char *last_sha1;
};

static void get_commits(struct metapack_writer *mw,
			const struct object_id *oid,
			void *data)
{
	struct write_cb *write_cb = (struct write_cb *)data;
	enum object_type type = sha1_object_info(oid->hash, NULL);
	struct commit *c;
	int p1 = -1, p2 = -1;

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
	if (!c->parents ||
	    (c->parents && c->parents->next && c->parents->next->next) ||
	    /* edge commits are out too */
	    find_pack_entry_pos(c->tree->object.oid.hash, mw->pack) == -1 ||
	    (p1 = find_pack_entry_pos(c->parents->item->object.oid.hash, mw->pack)) == -1 ||
	    (c->parents->next &&
	     (p2 = find_pack_entry_pos(c->parents->next->item->object.oid.hash, mw->pack)) == -1) ||
	    /*
	     * we set the 2nd parent the same as 1st parent as an
	     * indication that 2nd parent does not exist. Normal
	     * commits should never have two same parents, but just in
	     * case..
	     */
	    p1 == p2)
		return;

	/*
	 * Make sure we store the abbr sha-1 long enough to
	 * unambiguously identify any cached commits in the pack.
	 */
	while (write_cb->abbrev_len < 20 &&
	       write_cb->last_sha1 &&
	       !memcmp(write_cb->last_sha1, sha1, write_cb->abbrev_len))
		write_cb->abbrev_len++;
	/*
	 * A bit sensitive to metapack_writer_foreach. "sha1" must not
	 * be changed even after this function exits.
	 */
	write_cb->last_sha1 = sha1;

	write_cb->tail = &commit_list_insert(c, write_cb->tail)->next;
}

void commit_metapack_write(const char *idx)
{
	struct metapack_writer mw;
	struct commit_list *commits = NULL, *p;
	struct write_cb write_cb;
	uint32_t nr = 0;

	metapack_writer_init(&mw, idx, "commits", 1);

	write_cb.tail = &commits;
	write_cb.abbrev_len = 1;
	write_cb.last_sha1 = NULL;

	/* Figure out how many eligible commits we've got in this pack. */
	metapack_writer_foreach(&mw, get_commits, &write_cb);
	for (p = commits; p; p = p->next)
		nr++;

	metapack_writer_add_uint32(&mw, nr);
	metapack_writer_add_uint32(&mw, write_cb.abbrev_len);

	/* Then write an index of commit sha1s */
	for (p = commits; p; p = p->next)
		metapack_writer_add(&mw, p->item->object.oid.hash, write_cb.abbrev_len);

	/* Followed by the actual date/tree/parents data */
	for (p = commits; p; p = p->next) {
		struct commit *c = p->item;
		int pos;

		pos = find_pack_entry_pos(c->object.oid.hash, mw.pack);
		metapack_writer_add_uint32(&mw, pos);

		metapack_writer_add_uint32(&mw, c->date);

		pos = find_pack_entry_pos(c->tree->object.oid.hash, mw.pack);
		metapack_writer_add_uint32(&mw, pos);

		pos = find_pack_entry_pos(c->parents->item->object.oid.hash, mw.pack);
		metapack_writer_add_uint32(&mw, pos);

		if (c->parents->next) {
			struct object *o = &c->parents->next->item->object;
			pos = find_pack_entry_pos(o->oid.hash, mw.pack);
		}
		metapack_writer_add_uint32(&mw, pos);
	}

	metapack_writer_finish(&mw);
}
