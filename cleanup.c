#include "git-compat-util.h"
#include "cleanup.h"
#include "list.h"
#include "sigchain.h"

struct cleanup_node {
	cleanup_handler fn;
	struct volatile_list_head list;
};
static VOLATILE_LIST_HEAD(handler_list);

static void run_cleanup_handlers(int signo)
{
	volatile struct volatile_list_head *pos;
	list_for_each(pos, &handler_list) {
		struct cleanup_node *node =
			list_entry(pos, struct cleanup_node, list);
		node->fn(signo);
	}
}

static void cleanup_atexit_handler(void)
{
	run_cleanup_handlers(0);
}

static void cleanup_signal_handler(int signo)
{
	run_cleanup_handlers(signo);
	sigchain_pop(signo);
	raise(signo);
}

void cleanup_register(cleanup_handler fn)
{
	struct cleanup_node *node = xmalloc(sizeof(*node));
	node->fn = fn;
	INIT_LIST_HEAD(&node->list);
	volatile_list_add(&node->list, &handler_list);
}

void cleanup_init(void)
{
	atexit(cleanup_atexit_handler);
	sigchain_push(SIGINT, cleanup_signal_handler);
	sigchain_push(SIGHUP, cleanup_signal_handler);
	sigchain_push(SIGTERM, cleanup_signal_handler);
	sigchain_push(SIGQUIT, cleanup_signal_handler);
	sigchain_push(SIGPIPE, cleanup_signal_handler);
}
