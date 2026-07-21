#!/bin/sh

test_description='handling of timestamps before 1970'
. ./test-lib.sh

if test_have_prereq TIME_IS_64BIT,TIME_T_IS_64BIT
then
	test_set_prereq HAVE_64BIT_TIME
fi

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

test_expect_success 'timezone adjustment can cross the epoch' '
	test-tool date show:iso "-1 +0100" >actual &&
	echo "-1 +0100 -> 1970-01-01 00:59:59 +0100" >expect &&
	test_cmp expect actual
'

test_expect_success 'local timezone offset at second -1' '
	TZ=EST5 test-tool date show:iso-local "17999 +0000" >actual &&
	echo "17999 +0000 -> 1969-12-31 23:59:59 -0500" >expect &&
	test_cmp expect actual
'

test_expect_success HAVE_64BIT_TIME 'format dates around century leap-year boundaries' '
	test-tool date show:iso \
		"-2203977600 +0000" \
		"-2203891200 +0000" \
		"-2077833600 +0000" \
		"-2077747200 +0000" \
		"-2077660800 +0000" >actual &&
	cat >expect <<-\EOF &&
	-2203977600 +0000 -> 1900-02-28 00:00:00 +0000
	-2203891200 +0000 -> 1900-03-01 00:00:00 +0000
	-2077833600 +0000 -> 1904-02-28 00:00:00 +0000
	-2077747200 +0000 -> 1904-02-29 00:00:00 +0000
	-2077660800 +0000 -> 1904-03-01 00:00:00 +0000
	EOF
	test_cmp expect actual
'

test_expect_success HAVE_64BIT_TIME 'format dates before the Windows FILETIME epoch' '
	test-tool date show:iso \
		"-11644473600 +0000" \
		"-11644473601 +0000" >actual &&
	cat >expect <<-\EOF &&
	-11644473600 +0000 -> 1601-01-01 00:00:00 +0000
	-11644473601 +0000 -> 1600-12-31 23:59:59 +0000
	EOF
	test_cmp expect actual
'

test_expect_success 'local timezone observes DST before the epoch' '
	TZ=EST5EDT test-tool date show:iso-local \
		"-15854400 +0000" >actual &&
	echo "-15854400 +0000 -> 1969-07-01 08:00:00 -0400" >expect &&
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

test_expect_success 'negative approximate commit --date' '
	TZ=EST5 GIT_TEST_DATE_NOW=1 git commit --allow-empty -m foo \
		--date="2 seconds ago" &&
	git log --format="%at %ai" -1 >actual &&
	echo "-1 1969-12-31 18:59:59 -0500" >expect &&
	test_cmp expect actual
'

test_done
