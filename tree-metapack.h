#ifndef METAPACK_TREE_H
#define METAPACK_TREE_H

typedef void (*tree_metapack_fun)(const char *path,
				  unsigned old_mode,
				  unsigned new_mode,
				  const unsigned char *old_sha1,
				  const unsigned char *new_sha1,
				  void *data);

int tree_metapack(const unsigned char *sha1,
		  const unsigned char *parent,
		  tree_metapack_fun cb,
		  void *data);

void tree_metapack_write(const char *idx);

#endif
