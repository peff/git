#include "builtin.h"
#include "parse-options.h"
#include "commit-metapack.h"

static const char *metapack_usage[] = {
	N_("git metapack [options] <packindex...>"),
	NULL
};

#define METAPACK_COMMITS (1<<0)

static void metapack_one(const char *idx, int type)
{
	if (type & METAPACK_COMMITS)
		commit_metapack_write(idx);
}

static void metapack_all(int type)
{
	struct strbuf path = STRBUF_INIT;
	size_t dirlen;
	DIR *dh;
	struct dirent *de;

	strbuf_addstr(&path, get_object_directory());
	strbuf_addstr(&path, "/pack");
	dirlen = path.len;

	dh = opendir(path.buf);
	if (!dh)
		die_errno("unable to open pack directory '%s'", path.buf);
	while ((de = readdir(dh))) {
		if (!ends_with(de->d_name, ".idx"))
			continue;

		strbuf_addch(&path, '/');
		strbuf_addstr(&path, de->d_name);
		metapack_one(path.buf, type);
		strbuf_setlen(&path, dirlen);
	}

	closedir(dh);
	strbuf_release(&path);
}

int cmd_metapack(int argc, const char **argv, const char *prefix)
{
	int all = 0;
	int type = 0;
	struct option opts[] = {
		OPT_BOOL(0, "all", &all, N_("create metapacks for all packs")),
		OPT_BIT(0, "commits", &type, N_("create commit metapacks"),
			METAPACK_COMMITS),
		OPT_END()
	};

	save_commit_buffer = 0;
	argc = parse_options(argc, argv, prefix, opts, metapack_usage, 0);

	if (all && argc)
		usage_msg_opt(_("pack arguments do not make sense with --all"),
			      metapack_usage, opts);
	if (!type)
		usage_msg_opt(_("no metapack type specified"),
			      metapack_usage, opts);

	if (all)
		metapack_all(type);
	else
		for (; *argv; argv++)
			metapack_one(*argv, type);

	return 0;
}
