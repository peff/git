#ifndef USERDIFF_H
#define USERDIFF_H

#include "notes-cache.h"

struct index_state;
struct repository;

struct userdiff_funcname {
	const char *pattern;
	int cflags;
};

struct userdiff_textconv {
	const char *program;
	struct notes_cache *cache;
	int want_cache;
};

struct userdiff_driver {
	const char *name;
	const char *external;
	int binary;
	struct userdiff_funcname funcname;
	const char *word_regex;
	struct userdiff_textconv textconv;
};

int userdiff_config(const char *k, const char *v);
struct userdiff_driver *userdiff_find_by_name(const char *name);
struct userdiff_driver *userdiff_find_by_path(struct index_state *istate,
					      const char *path);

/*
 * Initialize any textconv-related fields in the driver and return it, or NULL
 * if it does not have textconv enabled at all.
 */
struct userdiff_textconv *userdiff_get_textconv(struct repository *r,
						struct userdiff_driver *driver);

#endif /* USERDIFF */
