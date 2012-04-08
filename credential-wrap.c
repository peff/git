#include "cache.h"
#include "credential.h"

int main(int argc, const char **argv)
{
	struct credential c = CREDENTIAL_INIT;
	const char *storage, *source, *action;

	if (argc != 4)
		usage("git credential-wrap <storage> <source> <action>");
	storage = argv[1];
	source = argv[2];
	action = argv[3];

	if (credential_read(&c, stdin) < 0)
		die("unable to read input credential");

	if (!strcmp(action, "get")) {
		credential_do(&c, storage, "get");
		if (!c.username || !c.password) {
			credential_do(&c, source, "get");
			if (!c.username || !c.password)
				return 0;
			credential_do(&c, storage, "store");
		}
		credential_write(&c, stdout);
	}
	else
		credential_do(&c, storage, action);

	return 0;
}
