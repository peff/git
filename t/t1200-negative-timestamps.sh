#!/bin/sh

test_description='handling of timestamps before 1970'
. ./test-lib.sh

test_expect_success 'create a commit with a negative timestamp' '
	tree=$(git hash-object -w -t tree --stdin </dev/null) &&
	commit=$(
		git hash-object -w -t commit --stdin <<-EOF
		tree $tree
		author $GIT_AUTHOR_NAME <$GIT_AUTHOR_EMAIL> -700000 +0100
		committer $GIT_COMMITTER_NAME <$GIT_COMMITTER_EMAIL> -700000 +0100

		subject
		EOF
	)
'

test_expect_success 'fsck does not complain about negative timestamps' '
	git fsck
'

test_expect_success 'show timestamp as unix date' '
	git log --date=unix --format=%ad -1 $commit >actual &&
	echo "-700000" >expect &&
	test_cmp expect actual
'

test_expect_success 'show timestamp in original zone' '
	git log --date=iso --format=%ad -1 $commit >actual &&
	echo "1969-12-23 22:33:20 +0100" >expect &&
	test_cmp expect actual
'

test_expect_success 'show timestamp in EST5' '
	TZ=EST5 git log --date=iso-local --format=%ad -1 $commit >actual &&
	echo "1969-12-23 16:33:20 -0500" >expect &&
	test_cmp expect actual
'

test_expect_success 'negative @-stamp in GIT_AUTHOR_DATE' '
	GIT_AUTHOR_DATE="@-700000 +0000" git commit --allow-empty -m foo &&
	git log --date=iso --format=%ad -1 >actual &&
	echo "1969-12-23 21:33:20 +0000" >expect &&
	test_cmp expect actual
'

test_expect_success 'negative @-stamp in commit --date' '
	git commit --allow-empty -m foo --date="@-700000 -0800" &&
	git log --date=iso --format=%ad -1 >actual &&
	echo "1969-12-23 13:33:20 -0800" >expect &&
	test_cmp expect actual
'

test_done
