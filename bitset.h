#ifndef BITSET_H
#define BITSET_H

/*
 * This header file provides functions for operating on an array of unsigned
 * characters as a bitmap. There is zero per-bitset storage overhead beyond the
 * actual number of stored bits (modulo some padding). This is efficient, but
 * makes the API harder to use. In particular, each bitset does not know how
 * long it is. It is the caller's responsibility to:
 *
 *   1. Never ask to get or set a bit outside of the allocated range.
 *
 *   2. Provide the allocated range to any functions which operate
 *      on the whole bitset (e.g., bitset_or).
 *
 *   3. Always feed bitsets of the same size to functions which require it
 *      (e.g., bitset_or).
 *
 *   4. Allocate the bitset as all-zeroes, either using xcalloc, or using
 *      memset(bits, 0, bitset_sizeof(num_bits)). Bitsets are padded up
 *      to the nearest byte, and some functions assume that padding between two
 *      bitsets will compare equal.
 *
 * It is mostly intended to be used with commit-slabs to store N bits per
 * commit. Here's an example:
 *
 *   define_commit_slab(bit_slab, unsigned char);
 *
 *   ... assume we want to store nr bits per commit ...
 *   struct bit_slab bits;
 *   init_bit_slab_with_stride(&bits, bitset_sizeof(nr));
 *
 *   ... set a bit (make sure 10 < nr!) ...
 *   bitset_set(bit_slab_at(&bits, commit), 10);
 *
 *   ... or get a bit ...
 *   if (bitset_get(bit_slab_at(&bits, commit), 5))
 *
 *   ... propagate bits to a parent commit ...
 *   bitset_or(bit_slab_at(&bits, parent),
 *	       bit_slab_at(&bits, commit),
 *	       nr);
 */

/*
 * Return the number of unsigned chars required to store num_bits bits.
 *
 * This is mostly used internally by the bitset functions, but you may need it
 * when allocating the bitset. Example:
 *
 *   bits = xcalloc(1, bitset_sizeof(nr));
 */
static inline unsigned bitset_sizeof(unsigned num_bits)
{
	return (num_bits + CHAR_BIT - 1) / CHAR_BIT;
}

/*
 * Set the bit at position "n". "n" is counted from zero, and must be
 * smaller than the num_bits given to bitset_sizeof when allocating the bitset.
 */
static inline void bitset_set(unsigned char *bits, unsigned n)
{
	bits[n / CHAR_BIT] |= 1 << (n % CHAR_BIT);
}

/*
 * Return the bit at position "n" (see bitset_set for a description of "n").
 */
static inline unsigned bitset_get(unsigned char *bits, unsigned n)
{
	return !!(bits[n / CHAR_BIT] & (1 << (n % CHAR_BIT)));
}

/*
 * Return true iff the bitsets contain the same bits. Each bitset should be the
 * same size, and should have been allocated using bitset_sizeof(num_bits).
 *
 * Note that it is not safe to check partial equality by providing a smaller
 * "num_bits" (we assume any bits beyond "num_bits" up to the next CHAR_BIT
 * boundary are zeroed padding).
 */
static inline int bitset_equal(unsigned char *a, unsigned char *b,
			       unsigned num_bits)
{
	unsigned i;
	for (i = bitset_sizeof(num_bits); i > 0; i--)
		if (*a++ != *b++)
			return 0;
	return 1;
}

/*
 * Bitwise-or the bitsets in "dst" and "src", and store the result in "dst".
 *
 * See bitset_equal for the definition of "num_bits".
 */
static inline void bitset_or(unsigned char *dst, const unsigned char *src,
			     unsigned num_bits)
{
	unsigned i;
	for (i = bitset_sizeof(num_bits); i > 0; i--)
		*dst++ |= *src++;
}

/*
 * Returns true iff the bitset contains all zeroes.
 *
 * See bitset_equal for the definition of "num_bits".
 */
static inline int bitset_empty(const unsigned char *bits, unsigned num_bits)
{
	unsigned i;
	for (i = bitset_sizeof(num_bits); i > 0; i--, bits++)
		if (*bits)
			return 0;
	return 1;
}

#endif /* BITSET_H */
