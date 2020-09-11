#include "test-tool.h"
#include "git-compat-util.h"
#include "thread-utils.h"

int cmd__online_cpus(int UNUSED(argc), const char **UNUSED(argv))
{
	printf("%d\n", online_cpus());
	return 0;
}
