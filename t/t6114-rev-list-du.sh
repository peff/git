#!/bin/sh

test_description='basic tests of rev-list --disk-usage'
. ./test-lib.sh

# we want a mix of reachable and unreachable, as well as
# objects in the bitmapped pack and some outside of it
test_expect_success 'set up repository' '
	test_commit one &&
	test_commit two &&
	git repack -adb &&
	git reset --hard HEAD^ &&
	test_commit three &&
	test_commit four &&
	git reset --hard HEAD^
'

# we can't really know what this is ahead of time (because it will
# vary with things like packing, or even zlib changes), but we'll
# assume that the regular rev-list and cat-file machinery works
# and compare the --disk-usage code to that.
test_expect_success 'generate expected size' '
	git rev-list --objects --all |
	cut -d" " -f1 |
	git cat-file --batch-check="%(objectsize:disk)" |
	perl -lne '\''$total += $_; END { print $total }'\'' >expect
'

test_expect_success 'internal du works without bitmaps' '
	git rev-list --disk-usage --all >actual &&
	test_cmp expect actual
'

test_expect_success 'internal du works with bitmaps' '
	git rev-list --disk-usage --all --use-bitmap-index >actual &&
	test_cmp expect actual
'

test_done
