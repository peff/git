#!/bin/sh

test_description='packing with adjustable in-window limits'
. ./perf-lib.sh

test_perf_default_repo

# The most interesting case for adjustable windows is when our heuristics often
# tell us we can skip a delta candidate without even trying to compute it. And
# a likely reason for that is that delta islands forbid the pairing.
#
# We can simulate an island setup where each island was "forked" at some time
# in the past from the main history (by just taking every 100th first-parent
# head). We'll clear out any extraneous refs and just give each fork a single
# copy of HEAD (at the time of forking) to keep things simple.
test_expect_success 'set up delta islands' '
	head=$(git rev-parse HEAD) &&
	git for-each-ref --format="delete %(refname)" |
	git update-ref --no-deref --stdin &&

	n=0 &&
	fork=0 &&
	git rev-list --first-parent $head |
	while read commit; do
		n=$((n+1)) &&
		if test "$n" = 100; then
			echo "create refs/forks/$fork/master $commit" &&
			fork=$((fork+1)) &&
			n=0 ||
			return 1
		fi
	done |
	git update-ref --stdin &&

	git config pack.island "refs/forks/([0-9]*)/"
'

# simulate a "repack -aif" without actually changing the on-disk state; we'll
# use no-reuse-delta because we want to see the effect on the delta search
pack_opts='--all --no-reuse-delta --delta-base-offset --delta-islands'
export pack_opts

test_perf 'window=10' '
	rm -f pack-*.pack &&
	git pack-objects $pack_opts --window=10 pack </dev/null
'

test_size 'pack size' '
	pack=$(echo pack-*.pack) &&
	wc -c <$pack
'

# use config to set slot limit so that we can compare against
# pre-slot-limit versions of Git
test_perf 'window=100, slots=10' '
	rm -f pack-*.pack &&
	git -c pack.windowslotlimit=10 \
		pack-objects $pack_opts --window=100 pack </dev/null
'

test_size 'pack size' '
	pack=$(echo pack-*.pack) &&
	wc -c <$pack
'

test_perf 'window=100, bytes=1m' '
	rm -f pack-*.pack &&
	git -c pack.windowbytelimit=1m \
		pack-objects $pack_opts --window=100 pack </dev/null
'

test_size 'pack size' '
	pack=$(echo pack-*.pack) &&
	wc -c <$pack
'

test_done
