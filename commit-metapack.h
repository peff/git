#ifndef METAPACK_COMMIT_H
#define METAPACK_COMMIT_H

int commit_metapack(const struct object_id *oid,
		    uint32_t *timestamp,
		    const unsigned char **tree,
		    const unsigned char **parent1,
		    const unsigned char **parent2);

void commit_metapack_write(const char *idx_file);

#endif
