#include "git-compat-util.h"
#include "compat/pipe-id.h"
#include "strbuf.h"

const char *pipe_id_get(int fd)
{
	static struct strbuf id = STRBUF_INIT;
	struct stat st;

	if (fstat(fd, &st) < 0 || !S_ISFIFO(st.st_mode))
		return NULL;

	strbuf_reset(&id);
	strbuf_addf(&id, "%lu:%lu",
		    (unsigned long)st.st_dev,
		    (unsigned long)st.st_ino);
	return id.buf;
}

int pipe_id_match(int fd, const char *id)
{
	struct stat st;
	const char *end;
	unsigned long dev, ino;

	if (fstat(fd, &st) < 0 || !S_ISFIFO(st.st_mode))
		return 0;

	dev = strtoul(id, (char **)&end, 10);
	if (*end++ != ':')
		return 0;
	ino = strtoul(end, (char **)&end, 10);
	if (*end)
		return 0;

	return dev == st.st_dev && ino == st.st_ino;
}
