#ifndef METAPACK_H
#define METAPACK_H

struct packed_git;
struct sha1file;

struct metapack_writer {
	char *path;
	struct packed_git *pack;
	struct sha1file *out;
};

void metapack_writer_init(struct metapack_writer *mw,
			  const char *pack_idx,
			  const char *name,
			  int version);
void metapack_writer_add(struct metapack_writer *mw, const void *data, int len);
void metapack_writer_add_uint32(struct metapack_writer *mw, uint32_t v);
void metapack_writer_finish(struct metapack_writer *mw);

typedef void (*metapack_writer_each_fn)(struct metapack_writer *,
					const unsigned char *sha1,
					void *data);
void metapack_writer_foreach(struct metapack_writer *mw,
			     metapack_writer_each_fn cb,
			     void *data);

struct metapack {
	unsigned char *mapped_buf;
	size_t mapped_len;

	unsigned char *data;
	size_t len;
};

int metapack_init(struct metapack *m,
		  struct packed_git *pack,
		  const char *name,
		  uint32_t *version);
void metapack_close(struct metapack *m);

#endif
