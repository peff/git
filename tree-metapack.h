#ifndef METAPACK_TREE_H
#define METAPACK_TREE_H

typedef void (*tree_metapack_fun)(const char *path,
				  unsigned old_mode,
				  unsigned new_mode,
				  const struct object_id *old_sha1,
				  const struct object_id *new_sha1,
				  void *data);

int tree_metapack(const struct object_id *sha1,
		  const struct object_id *parent,
		  tree_metapack_fun cb,
		  void *data);

void tree_metapack_write(const char *idx);

#endif
