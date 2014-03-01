#include "cache.h"
#include "diff.h"
#include "diffcore.h"
#include "utf8.h"
#include "icu.h"

#include <unicode/ucsdet.h>

void diff_filespec_convert_text(struct diff_filespec *one,
				int min_confidence)
{
	UErrorCode status = U_ZERO_ERROR;
	UCharsetDetector *ucsd;
	const UCharsetMatch *match;

	if (diff_populate_filespec(one, 0) < 0)
		return;

	ucsd = ucsdet_open(&status);
	ucsdet_setText(ucsd, one->data, one->size, &status);
	match = ucsdet_detect(ucsd, &status);

	if (match && ucsdet_getConfidence(match, &status) >= min_confidence) {
		const char *from = ucsdet_getName(match, &status);
		const char *to = get_log_output_encoding();

		if (!same_encoding(from, to)) {
			char *buf;
			int len;

			buf = reencode_string_len(one->data, one->size,
						  to, from, &len);
			if (buf) {
				diff_free_filespec_data(one);
				one->data = buf;
				one->size = len;
				one->should_free = 1;
			}
		}
	}

	ucsdet_close(ucsd);
}
