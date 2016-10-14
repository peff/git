#include "cache.h"
#include "commit.h"
#include "diff.h"
#include "diffcore.h"
#include "revision.h"
#include "config.h"
#include "builtin.h"

static const char diff_pairs_usage[] =
"git diff-pairs [diff-options]\n"
"\n"
"Reads pairs of blobs from stdin in 'diff-tree -z' syntax:\n"
"\n"
"  :<mode_a> <mode_b> <sha1_a> <sha1_b> <type>\\0<path>\0[path2\0]\n"
"\n"
"and outputs the diff for each a/b pair to stdout.";

static unsigned parse_mode(const char *mode, const char **endp)
{
	unsigned long ret;

	errno = 0;
	ret = strtoul(mode, (char **)endp, 8);
	if (errno || *endp == mode || *(*endp)++ != ' ' || (unsigned)ret != ret)
		die("unable to parse mode: %s", mode);
	return ret;
}

static void parse_oid(const char *p, struct object_id *oid, const char **endp)
{
	if (parse_oid_hex(p, oid, endp) || *(*endp)++ != ' ')
		die("unable to parse object id: %s", p);
}

static unsigned short parse_score(const char *score)
{
	unsigned long ret;
	char *endp;

	errno = 0;
	ret = strtoul(score, &endp, 10);
	ret *= MAX_SCORE / 100;
	if (errno || endp == score || *endp || (unsigned short)ret != ret)
		die("unable to parse rename/copy score: %s", score);
	return ret;
}

/*
 * The pair-creation is mostly done by diff_change and diff_addremove,
 * which queue the filepair without returning it. So we have to resort
 * to pulling it out of the global diff queue.
 */
static void set_pair_status(char status)
{
	/*
	 * If we have no items in the queue, for some reason the pair wasn't
	 * worth queueing. This generally shouldn't happen (since it means
	 * dropping some parts of the diff), but the user can trigger it with
	 * things like --ignore-submodules. If they do, the only sensible thing
	 * is for us to play along and skip it.
	 */
	if (!diff_queued_diff.nr)
		return;

	diff_queued_diff.queue[0]->status = status;
}

int cmd_diff_pairs(int argc, const char **argv, const char *prefix)
{
	struct rev_info revs;
	struct strbuf meta = STRBUF_INIT;
	struct strbuf path = STRBUF_INIT;
	struct strbuf path_dst = STRBUF_INIT;

	if (argc > 1 && !strcmp(argv[1], "-h"))
		usage(diff_pairs_usage);

	init_revisions(&revs, prefix);
	git_config(git_diff_basic_config, NULL);
	revs.disable_stdin = 1;
	argc = setup_revisions(argc, argv, &revs, NULL);

	/* Don't allow pathspecs at all. */
	if (argc > 1)
		usage(diff_pairs_usage);

	if (!revs.diffopt.output_format)
		revs.diffopt.output_format = DIFF_FORMAT_RAW;

	while (1) {
		unsigned mode_a, mode_b;
		struct object_id oid_a, oid_b;
		char status;
		const char *p;

		if (strbuf_getline_nul(&meta, stdin) == EOF)
			break;

		p = meta.buf;
		if (*p == ':')
			p++;

		mode_a = parse_mode(p, &p);
		mode_b = parse_mode(p, &p);

		parse_oid(p, &oid_a, &p);
		parse_oid(p, &oid_b, &p);

		status = *p++;

		if (strbuf_getline_nul(&path, stdin) == EOF)
			die("got EOF while reading path");

		switch (status) {
		case DIFF_STATUS_ADDED:
			diff_addremove(&revs.diffopt, '+',
				       mode_b, &oid_b,
				       1, path.buf, 0);
			set_pair_status(status);
			break;

		case DIFF_STATUS_DELETED:
			diff_addremove(&revs.diffopt, '-',
				       mode_a, &oid_a,
				       1, path.buf, 0);
			set_pair_status(status);
			break;

		case DIFF_STATUS_TYPE_CHANGED:
		case DIFF_STATUS_MODIFIED:
			diff_change(&revs.diffopt,
				    mode_a, mode_b,
				    &oid_a, &oid_b,
				    1, 1, path.buf, 0, 0);
			set_pair_status(status);
			break;

		case DIFF_STATUS_RENAMED:
		case DIFF_STATUS_COPIED:
			{
				struct diff_filespec *a, *b;
				struct diff_filepair *pair;

				if (strbuf_getline_nul(&path_dst, stdin) == EOF)
					die("got EOF while reading secondary path");

				a = alloc_filespec(path.buf);
				b = alloc_filespec(path_dst.buf);
				fill_filespec(a, &oid_a, 1, mode_a);
				fill_filespec(b, &oid_b, 1, mode_b);

				pair = diff_queue(&diff_queued_diff, a, b);
				pair->status = status;
				pair->score = parse_score(p);
				pair->renamed_pair = 1;
			}
			break;

		default:
			die("unknown diff status: %c", status);
		}

		diff_flush(&revs.diffopt);
	}

	return 0;
}
