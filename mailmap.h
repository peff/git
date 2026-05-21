#ifndef MAILMAP_H
#define MAILMAP_H

#include "string-list.h"

struct repository;

struct mailmap {
	struct string_list map;
};

#define MAILMAP_INIT { STRING_LIST_INIT_DUP }

void mailmap_init(struct mailmap *map);

/* Flags for read_mailmap_file() */
#define MAILMAP_NOFOLLOW (1<<0)

int read_mailmap_file(struct mailmap *map, const char *filename,
		      unsigned flags);
int read_mailmap_blob(struct repository *repo, struct mailmap *map,
		      const char *name);

int read_mailmap(struct repository *repo, struct mailmap *map);
void clear_mailmap(struct mailmap *map);

int map_user(struct mailmap *map,
			 const char **email, size_t *emaillen, const char **name, size_t *namelen);

#endif
