#include "builtin.h"
#include "credential.h"

int cmd_credential_wrap(int argc, const char **argv,
			const char *prefix UNUSED,
			struct repository *repo UNUSED)
{
	struct credential c = CREDENTIAL_INIT;
	const char *storage, *source, *action;

	if (argc != 4)
		usage("git credential-wrap <storage> <source> <action>");
	storage = argv[1];
	source = argv[2];
	action = argv[3];

	if (credential_read(&c, stdin, CREDENTIAL_OP_INITIAL) < 0)
		die("unable to read input credential");

	if (!strcmp(action, "get")) {
		credential_do(&c, storage, "get");
		if (!c.username || !c.password) {
			credential_do(&c, source, "get");
			if (!c.username || !c.password)
				return 0;
			credential_do(&c, storage, "store");
		}
		credential_write(&c, stdout, CREDENTIAL_OP_RESPONSE);
	}
	else
		credential_do(&c, storage, action);

	return 0;
}
