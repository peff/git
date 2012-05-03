#include "cache.h"
#include "dumpstat/dumpstat.h"

#ifndef DUMPSTAT_ZEROMQ
struct dumpstat_writer *dumpstat_to_zeromq(const char *endpoint)
{
	warning("zeromq dumpstat support not built");
	return NULL;
}

#else

#include <zmq.h>

static char id[256];
static void *context;
static void *mq;

static int dumpstat_zeromq_write(const char *buf, size_t len)
{
	zmq_msg_t msg;

	zmq_msg_init_size(&msg, len);
	memcpy(zmq_msg_data(&msg), buf, len);
	if (zmq_send(mq, &msg, 0) < 0) {
		warning("unable to write to zeromq: %s", strerror(errno));
		return -1;
	}
	return 0;
}

struct dumpstat_writer *dumpstat_to_zeromq(const char *endpoint)
{
	static struct dumpstat_writer writer = {
		dumpstat_zeromq_write
	};
	int len;

	len = snprintf(id, sizeof(id), "%d@", (int)getpid());
	if (gethostname(id + len, sizeof(id) - len) < 0) {
		warning("unable to gethostname: %s", strerror(errno));
		return NULL;
	}

	context = zmq_init(1);
	mq = zmq_socket(context, ZMQ_PUB);
	if (!mq || zmq_connect(mq, endpoint) < 0) {
		warning("unable to open zeromq socket: %s", strerror(errno));
		return NULL;
	}

	return &writer;
}

#endif /* DUMPSTAT_ZEROMQ */
