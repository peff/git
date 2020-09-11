#include "builtin.h"
#include "strvec.h"

static const char unpack_usage[] = "git unpack-objects [-n] [-q] [-r] [--strict]";

int cmd_unpack_objects(int argc, const char **argv, const char *prefix)
{
	struct strvec cmd = STRVEC_INIT;
	int i;
	int quiet = !isatty(2);

	strvec_pushl(&cmd, "index-pack", "--unpack", "--stdin", NULL);

	for (i = 1 ; i < argc; i++) {
		const char *arg = argv[i];

		if (*arg == '-') {
			if (!strcmp(arg, "-n")) {
				strvec_push(&cmd, "--verify");
				continue;
			}
			if (!strcmp(arg, "-q")) {
				quiet = 1;
				continue;
			}
			if (!strcmp(arg, "-r")) {
				warning("option -r is deprecated and does nothing");
				continue;
			}
			if (!strcmp(arg, "--strict") ||
			    starts_with(arg, "--strict=") ||
			    starts_with(arg, "--pack_header=") ||
			    starts_with(arg, "--max-input-size=")) {
				strvec_push(&cmd, arg);
				continue;
			}
			usage(unpack_usage);
		}

		/* We don't take any non-flag arguments now.. Maybe some day */
		usage(unpack_usage);
	}

	if (!quiet)
		strvec_push(&cmd, "-v");

	return cmd_index_pack(cmd.nr, cmd.v, prefix);
}
