#include "cache.h"
#include "dumpstat/dumpstat.h"

static const char *path;

static int dumpstat_file_write(const char *buf, size_t len)
{
	int fd = open(path, O_WRONLY|O_CREAT|O_APPEND, 0666);
	int r;

	if (fd < 0)
		return -1;

	r = write_in_full(fd, buf, len);
	if (r < 0)
		warning("unable to write to '%s': %s", path, strerror(errno));

	close(fd);
	return r;
}

struct dumpstat_writer *dumpstat_to_file(const char *s)
{
	static struct dumpstat_writer writer = {
		dumpstat_file_write
	};

	path = s;
	return &writer;
}
