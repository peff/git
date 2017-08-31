#include "git-compat-util.h"
#include "sigchain.h"

#define SIGCHAIN_MAX_SIGNALS 32

struct sigchain_signal {
	struct sigaction *old;
	int n;
	int alloc;
};
static struct sigchain_signal signals[SIGCHAIN_MAX_SIGNALS];

static void check_signum(int sig)
{
	if (sig < 1 || sig >= SIGCHAIN_MAX_SIGNALS)
		BUG("signal out of range: %d", sig);
}

/*
 * On platforms that have it, we can use sigaction. But otherwise we just fake
 * it by calling signal() and totally ignoring the sa_flags or sa_mask fields.
 */
static int maybe_sigaction(int sig,
			  struct sigaction *sa,
			  struct sigaction *old)
{
#ifndef GIT_WINDOWS_NATIVE
	return sigaction(sig, sa, old);
#else
	old->sa_handler = signal(sig, sa->sa_handler);
	return old->sa_handler == SIG_ERR ? -1 : 0;
#endif
}

static int sigchain_push_with_mask(int sig, sigchain_fun f, const sigset_t *mask)
{
	struct sigaction sa;
	struct sigchain_signal *s = signals + sig;
	check_signum(sig);

	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = f;
	sa.sa_flags = SA_RESTART;
#ifndef GIT_WINDOWS_NATIVE
	if (mask)
		memcpy(&sa.sa_mask, mask, sizeof(*mask));
#endif

	ALLOC_GROW(s->old, s->n + 1, s->alloc);
	if (maybe_sigaction(sig, &sa, &s->old[s->n]) < 0)
		return -1;

	s->n++;
	return 0;
}

int sigchain_push(int sig, sigchain_fun f)
{
	return sigchain_push_with_mask(sig, f, NULL);
}

int sigchain_pop(int sig)
{
	struct sigaction dummy;
	struct sigchain_signal *s = signals + sig;
	check_signum(sig);
	if (s->n < 1)
		return 0;

	if (maybe_sigaction(sig, &s->old[s->n - 1], &dummy) < 0)
		return -1;
	s->n--;
	return 0;
}

void sigchain_push_common(sigchain_fun f)
{
	sigset_t mask;

	sigemptyset(&mask);
	sigaddset(&mask, SIGINT);
	sigaddset(&mask, SIGHUP);
	sigaddset(&mask, SIGTERM);
	sigaddset(&mask, SIGQUIT);
	sigaddset(&mask, SIGPIPE);

	sigchain_push_with_mask(SIGINT, f, &mask);
	sigchain_push_with_mask(SIGHUP, f, &mask);
	sigchain_push_with_mask(SIGTERM, f, &mask);
	sigchain_push_with_mask(SIGQUIT, f, &mask);
	sigchain_push_with_mask(SIGPIPE, f, &mask);
}

void sigchain_pop_common(void)
{
	sigchain_pop(SIGPIPE);
	sigchain_pop(SIGQUIT);
	sigchain_pop(SIGTERM);
	sigchain_pop(SIGHUP);
	sigchain_pop(SIGINT);
}
