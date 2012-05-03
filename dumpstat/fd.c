#include "cache.h"
#include "dumpstat/dumpstat.h"

static int fd;

static int dumpstat_fd_write(const char *buf, size_t len)
{
	if (write_in_full(fd, buf, len) < 0) {
		warning("unable to write to fd %d: %s", fd, strerror(errno));
		return -1;
	}
	return 0;
}

struct dumpstat_writer *dumpstat_to_fd(const char *s)
{
	static struct dumpstat_writer writer = {
		dumpstat_fd_write
	};

	fd = atoi(s);
	return &writer;
}
