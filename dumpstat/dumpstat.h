#ifndef DUMPSTAT_H
#define DUMPSTAT_H

enum dumpstat_type {
	DUMPSTAT_STRING = 0,
	DUMPSTAT_BOOL,
	DUMPSTAT_UINT
};

struct dumpstat {
	const char *name;
	unsigned long timestamp;

	enum dumpstat_type type;
	union {
		const char *string;
		int boolean;
		struct {
			uintmax_t cur;
			uintmax_t sent;
			uintmax_t freq;
		} uint;
	} v;

	int initialized;
	struct dumpstat *next;
};

#define DUMPSTAT_INIT(name) { name }

void dumpstat_identity(const char *value);
void dumpstat_flush(struct dumpstat *ds);
void dumpstat_string(struct dumpstat *ds, const char *value);
void dumpstat_bool(struct dumpstat *ds, int value);
void dumpstat_uint(struct dumpstat *ds, uintmax_t value);
void dumpstat_increment(struct dumpstat *ds, uintmax_t value, uintmax_t freq);

struct dumpstat_writer {
	int (*write)(const char *buf, size_t len);
};
struct dumpstat_writer *dumpstat_to_file(const char *path);
struct dumpstat_writer *dumpstat_to_fd(const char *desc);

struct dumpstat_formatter {
	void (*start)(void);
	void (*add)(const struct dumpstat *);
	void (*finish)(void);

	const char *buf;
	size_t len;
};
struct dumpstat_formatter *dumpstat_format_json(void);

#endif /* DUMPSTAT_H */
