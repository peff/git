#ifndef ICU_H
#define ICU_H

#ifndef HAVE_LIBICU
#define diff_filespec_convert_text(df,confidence)
#else

void diff_filespec_convert_text(struct diff_filespec *one,
				int min_confidence);

#endif /* HAVE_LIBICU */

#endif /* ICU_H */
