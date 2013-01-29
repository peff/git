#include "cache.h"
#include "metapack.h"
#include "csum-file.h"
#include "packfile.h"

static struct sha1file *create_meta_tmp(void)
{
	struct strbuf tmp = STRBUF_INIT;
	int fd;

	fd = odb_mkstemp(&tmp, "pack/tmp_meta_XXXXXX");
	return sha1fd(fd, strbuf_detach(&tmp, NULL));
}

static void write_meta_header(struct metapack_writer *mw, const char *id,
			      uint32_t version)
{
	version = htonl(version);

	sha1write(mw->out, "META", 4);
	sha1write(mw->out, "\0\0\0\1", 4);
	sha1write(mw->out, mw->pack->sha1, 20);
	sha1write(mw->out, id, 4);
	sha1write(mw->out, &version, 4);
}

void metapack_writer_init(struct metapack_writer *mw,
			  const char *pack_idx,
			  const char *name,
			  int version)
{
	struct strbuf path = STRBUF_INIT;

	memset(mw, 0, sizeof(*mw));

	mw->pack = add_packed_git(pack_idx, strlen(pack_idx), 1);
	if (!mw->pack || open_pack_index(mw->pack))
		die("unable to open packfile '%s'", pack_idx);

	strbuf_addstr(&path, pack_idx);
	strbuf_strip_suffix(&path, ".idx");
	strbuf_addch(&path, '.');
	strbuf_addstr(&path, name);
	mw->path = strbuf_detach(&path, NULL);

	mw->out = create_meta_tmp();
	write_meta_header(mw, name, version);
}

void metapack_writer_finish(struct metapack_writer *mw)
{
	const char *tmp = mw->out->name;

	sha1close(mw->out, NULL, CSUM_FSYNC);
	if (rename(tmp, mw->path))
		die_errno("unable to rename temporary metapack file");

	close_pack_index(mw->pack);
	free(mw->pack);
	free(mw->path);
	free((char *)tmp);
}

void metapack_writer_add(struct metapack_writer *mw, const void *data, int len)
{
	sha1write(mw->out, data, len);
}

void metapack_writer_add_uint32(struct metapack_writer *mw, uint32_t v)
{
	v = htonl(v);
	metapack_writer_add(mw, &v, 4);
}

void metapack_writer_foreach(struct metapack_writer *mw,
			     metapack_writer_each_fn cb,
			     void *data)
{
	const unsigned char *sha1;
	uint32_t i = 0;

	/*
	 * We'll feed these to the callback in sorted order, since that is the
	 * order that they are stored in the .idx file.
	 */
	while ((sha1 = nth_packed_object_sha1(mw->pack, i++)))
		cb(mw, sha1, data);
}

int metapack_init(struct metapack *m,
		  struct packed_git *pack,
		  const char *name,
		  uint32_t *version)
{
	struct strbuf path = STRBUF_INIT;
	int fd;
	struct stat st;

	memset(m, 0, sizeof(*m));

	strbuf_addstr(&path, pack->pack_name);
	strbuf_strip_suffix(&path, ".pack");
	strbuf_addch(&path, '.');
	strbuf_addstr(&path, name);

	fd = open(path.buf, O_RDONLY);
	strbuf_release(&path);
	if (fd < 0)
		return -1;
	if (fstat(fd, &st) < 0) {
		close(fd);
		return -1;
	}

	m->mapped_len = xsize_t(st.st_size);
	m->mapped_buf = xmmap(NULL, m->mapped_len, PROT_READ, MAP_PRIVATE, fd, 0);
	close(fd);

	m->data = m->mapped_buf;
	m->len = m->mapped_len;

	if (m->len < 8 ||
	    memcmp(m->mapped_buf, "META", 4) ||
	    memcmp(m->mapped_buf + 4, "\0\0\0\1", 4)) {
		warning("metapack '%s' for '%s' does not have a valid header",
			name, pack->pack_name);
		metapack_close(m);
		return -1;
	}
	m->data += 8;
	m->len -= 8;

	if (m->len < 20 || hashcmp(m->data, pack->sha1)) {
		warning("metapack '%s' for '%s' does not match pack sha1",
			name, pack->pack_name);
		metapack_close(m);
		return -1;
	}
	m->data += 20;
	m->len -= 20;

	if (m->len < 8 || memcmp(m->data, name, 4)) {
		warning("metapack '%s' for '%s' does not have expected header id",
			name, pack->pack_name);
		metapack_close(m);
		return -1;
	}
	memcpy(version, m->data + 4, 4);
	*version = ntohl(*version);
	m->data += 8;
	m->len -= 8;

	return 0;
}

void metapack_close(struct metapack *m)
{
	munmap(m->mapped_buf, m->mapped_len);
}
