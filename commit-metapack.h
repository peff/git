#ifndef METAPACK_COMMIT_H
#define METAPACK_COMMIT_H

int commit_metapack(const struct object_id *oid,
		    uint32_t *timestamp,
		    uint32_t *generation,
		    struct object_id *tree,
		    struct object_id *parent1,
		    struct object_id *parent2);

void commit_metapack_write(const char *idx_file);

int have_commit_metapacks(void);

#endif
