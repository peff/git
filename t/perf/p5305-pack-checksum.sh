#!/bin/sh

test_description='Tests performance of recomputing pack checksums'
. ./perf-lib.sh

test_perf_fresh_repo

pack_size=${GIT_PERF_PACK_CHECKSUM_SIZE:-134217728}
pack_limit=$((pack_size / 2))
export pack_size pack_limit

test_expect_success 'set up large objects' '
	# The small change to "big" makes the second version a good delta
	# against the first. The thin pack will contain that delta but omit
	# its base, which index-pack must append before fixing the header.
	test-tool genrandom base $pack_size >big &&
	git add big &&
	git commit -m base &&
	base=$(git rev-parse HEAD) &&

	# Without another object, the thin pack would contain little besides
	# the small delta. Include an unrelated large object so that fixing
	# the header has to re-read and checksum a large amount of existing
	# pack data. It also gives pack-objects enough data to split below.
	printf foo >>big &&
	test-tool genrandom unrelated $pack_size >unrelated &&
	git add big unrelated &&
	git commit -m tip &&
	tip=$(git rev-parse HEAD) &&

	printf "%s\n^%s\n" "$tip" "$base" |
	git pack-objects --revs --thin --stdout >thin.pack &&

	# Use distinct contents here so that fast-import cannot notice that
	# the object is already in the repository and skip writing it.
	{
		echo blob &&
		echo "data $pack_size" &&
		test-tool genrandom fast-import $pack_size
	} >fast-import.in &&

	git repack -ad
'

test_perf 'split pack with pack-objects' \
	--setup 'rm -f pack-big-*' '
	git pack-objects --all --max-pack-size=$pack_limit pack-big </dev/null
'

test_perf 'fix thin pack with index-pack' \
	--setup 'rm -rf index.git && git clone -q --bare . index.git' '
	GIT_DIR=index.git git index-pack --stdin --fix-thin <thin.pack
'

test_perf 'fix pack header with fast-import' \
	--setup 'rm -rf import.git && git init -q --bare import.git' '
	GIT_DIR=import.git git -c fastimport.unpacklimit=0 fast-import \
		<fast-import.in
'

test_done
