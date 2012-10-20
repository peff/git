#ifndef BLAME_TREE_H
#define BLAME_TREE_H

#include "commit.h"
#include "diff.h"
#include "revision.h"
#include "string-list.h"

struct blame_tree {
	struct string_list paths;
	struct rev_info rev;
};

void blame_tree_init(struct blame_tree *,
		     int argc, const char **argv, const char *prefix);
void blame_tree_release(struct blame_tree *);

typedef void (*blame_tree_callback)(const char *path,
				    const struct commit *commit,
				    void *data);
int blame_tree_run(struct blame_tree *,
		   blame_tree_callback cb,
		   void *data);

#endif /* BLAME_TREE_H */
