#ifndef PIPE_ID_H
#define PIPE_ID_H

/**
 * This module allows callers to save a string pipe identifier, and later find
 * out whether a file descriptor refers to the same pipe.
 *
 * The ids should be opaque to the callers, as their implementation may be
 * system dependent. The generated ids can be used between processes on the
 * same system, but are not portable between systems, or even between different
 * versions of git.
 */

/**
 * Returns a string representing the pipe-id of the file descriptor `fd`, or
 * NULL if an error occurs. Note that the return value may be invalidated by
 * subsequent calls to pipe_id_get.
 */
const char *pipe_id_get(int fd);

/**
 * Returns 1 if the pipe at `fd` matches the id `id`, or 0 otherwise (or if an
 * error occurs).
 */
int pipe_id_match(int fd, const char *id);

#endif /* PIPE_ID_H */
