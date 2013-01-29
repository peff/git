#include "cache.h"
#include "commit-metapack.h"
#include "metapack.h"
#include "commit.h"
#include "sha1-lookup.h"
#include "packfile.h"

struct commit_metapack {
	struct metapack mp;
	uint32_t nr;
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
	memcpy(&it->nr, it->mp.data, 4);
	it->nr = ntohl(it->nr);

	/*
	 * We need 84 bytes for each entry: sha1(20), date(4), tree(20),
	 * parents(40).
	 */
	if (it->mp.len < (84 * it->nr + 4)) {
		warning("commit metapack for '%s' is truncated", pack->pack_name);
		metapack_close(&it->mp);
		free(it);
		return NULL;
	}

	it->index = it->mp.data + 4;
	it->data = it->index + 20 * it->nr;

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

int commit_metapack(const struct object_id *oid,
		    uint32_t *timestamp,
		    unsigned char **tree,
		    unsigned char **parent1,
		    unsigned char **parent2)
{
	struct commit_metapack *p;

	prepare_commit_metapacks();
	for (p = commit_metapacks; p; p = p->next) {
		unsigned char *data;
		int pos = sha1_entry_pos(p->index, 20, 0, 0, p->nr, p->nr, oid->hash);
		if (pos < 0)
			continue;

		/* timestamp(4) + tree(20) + parents(40) */
		data = p->data + 64 * pos;
		*timestamp = *(uint32_t *)data;
		*timestamp = ntohl(*timestamp);
		data += 4;
		*tree = data;
		data += 20;
		*parent1 = data;
		data += 20;
		*parent2 = data;

		return 0;
	}

	return -1;
}

static void get_commits(struct metapack_writer *mw,
			const struct object_id *oid,
			void *data)
{
	struct commit_list ***tail = data;
	enum object_type type = sha1_object_info(oid->hash, NULL);
	struct commit *c;

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
	    (c->parents && c->parents->next && c->parents->next->next))
		return;

	*tail = &commit_list_insert(c, *tail)->next;
}

void commit_metapack_write(const char *idx)
{
	struct metapack_writer mw;
	struct commit_list *commits = NULL, *p;
	struct commit_list **tail = &commits;
	uint32_t nr = 0;

	metapack_writer_init(&mw, idx, "commits", 1);

	/* Figure out how many eligible commits we've got in this pack. */
	metapack_writer_foreach(&mw, get_commits, &tail);
	for (p = commits; p; p = p->next)
		nr++;
	metapack_writer_add_uint32(&mw, nr);

	/* Then write an index of commit sha1s */
	for (p = commits; p; p = p->next)
		metapack_writer_add(&mw, p->item->object.oid.hash, 20);

	/* Followed by the actual date/tree/parents data */
	for (p = commits; p; p = p->next) {
		struct commit *c = p->item;
		metapack_writer_add_uint32(&mw, c->date);
		metapack_writer_add(&mw, c->tree->object.oid.hash, 20);
		metapack_writer_add(&mw, c->parents->item->object.oid.hash, 20);
		metapack_writer_add(&mw,
				    c->parents->next ?
				    c->parents->next->item->object.oid.hash :
				    null_sha1, 20);
	}

	metapack_writer_finish(&mw);
}
