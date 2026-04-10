#ifndef CLEANUP_H
#define CLEANUP_H

typedef void (*cleanup_handler)(int signo);

void cleanup_init(void);
void cleanup_register(cleanup_handler fn);

#endif /* CLEANUP_H */
