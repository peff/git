#include "cache.h"
#include "dir.h"
#include "commit.h"
#include "revision.h"
#include "remote.h"
#include "builtin.h"
#include "parse-options.h"
#include "pack-bitmap.h"

static const char * const ahead_behind_usage[] = {
	N_("git ahead-behind [--base=branch] [other...]"),
	NULL
};

static struct object_array_entry *find_pending(struct object_array *array,
					       int flags,
					       int mask)
{
	int i;
	for (i = 0; i < array->nr; i++) {
		struct object_array_entry *ent = array->objects + i;
		if ((ent->item->flags & mask) == flags)
			return ent;
	}
	return NULL;
}

static struct commit *default_base = NULL;
static const char *base_ref = "master";

static void handle_arg(struct rev_info *revs, const char *revarg)
{
	struct object_array_entry *tip_ent, *base_ent;
	struct commit *tip, *base;
	int ahead, behind;

	if (handle_revision_arg(revarg, revs, 0, REVARG_CANNOT_BE_FILENAME))
		die("bad revision '%s'", revarg);

	base_ent = find_pending(&revs->pending, UNINTERESTING, UNINTERESTING);
	if (base_ent)
		base = lookup_commit_reference(the_repository, &base_ent->item->oid);
	else if (default_base)
		base = default_base;
	else
		base = default_base = lookup_commit_reference_by_name(base_ref);
	if (!base)
		die("missing base for ahead-behind stats");

	tip_ent = find_pending(&revs->pending, 0, UNINTERESTING);
	if (!tip_ent)
		die("not an interesting ref: %s", revarg);
	tip = lookup_commit_reference(the_repository, &tip_ent->item->oid);
	if (!tip)
		die("failed to lookup commit ref %s", oid_to_hex(&tip_ent->item->oid));

	revision_ahead_behind(tip, base, &ahead, &behind, AHEAD_BEHIND_FULL);
	printf("%s %d %d\n", tip_ent->name, ahead, behind);

	object_array_clear(&revs->pending);
}

int cmd_ahead_behind(int argc, const char **argv, const char *prefix)
{
	int from_stdin = 0;

	struct option ahead_behind_opts[] = {
		OPT_STRING('b', "base", &base_ref, N_("base"), N_("base reference to process")),
		OPT_BOOL( 0 , "stdin", &from_stdin, N_("read rev names from stdin")),
		OPT_END()
	};

	struct rev_info revs;

	argc = parse_options(argc, argv, NULL, ahead_behind_opts,
			     ahead_behind_usage, 0);

	init_revisions(&revs, NULL);

	if (from_stdin) {
		struct strbuf line = STRBUF_INIT;

		while (strbuf_getline(&line, stdin) != EOF) {
			if (!line.len)
				break;

			handle_arg(&revs, line.buf);
		}

		strbuf_release(&line);
	} else {
		int i;

		for (i = 0; i < argc; ++i)
			handle_arg(&revs, argv[i]);
	}

	return 0;
}
