#!/bin/sh

test_description='basic blame-tree tests'
. ./test-lib.sh

test_expect_success 'setup' '
	test_commit 1 file &&
	mkdir a &&
	test_commit 2 a/file &&
	mkdir a/b &&
	test_commit 3 a/b/file
'

test_expect_success 'cannot blame two trees' '
	test_must_fail git blame-tree HEAD HEAD~1
'

check_blame() {
	cat >expect &&
	git blame-tree "$@" >actual &&
	git name-rev --stdin --name-only --tags <actual >tmp &&
	mv tmp actual &&
	tr '\t' ' ' <actual >tmp &&
	mv tmp actual &&
	sort <actual >tmp &&
	mv tmp actual &&
	test_cmp expect actual
}

test_expect_success 'blame recursive' '
	check_blame <<-\EOF
	1 file
	2 a/file
	3 a/b/file
	EOF
'

test_expect_success 'blame root' '
	check_blame --max-depth=0 <<-\EOF
	1 file
	3 a
	EOF
'

test_expect_success 'blame subdir' '
	check_blame --max-depth=1 a <<-\EOF
	2 a/file
	3 a/b
	EOF
'

test_expect_success 'blame from non-HEAD commit' '
	check_blame --max-depth=0 HEAD^ <<-\EOF
	1 file
	2 a
	EOF
'

test_expect_success 'blame from subdir defaults to root' '(
	cd a &&
	check_blame --max-depth=0 <<-\EOF
	1 file
	3 a
	EOF
)'

test_expect_success 'blame from subdir uses relative pathspecs' '(
	cd a &&
	check_blame --max-depth=1 b <<-\EOF
	3 a/b/file
	EOF
)'

test_expect_success 'limit blame traversal by count' '
	check_blame --max-depth=0 -1 <<-\EOF
	3 a
	^2 file
	EOF
'

test_expect_success 'limit blame traversal by commit' '
	check_blame --max-depth=0 HEAD~2..HEAD <<-\EOF
	3 a
	^1 file
	EOF
'

test_expect_success 'only blame files in the current tree' '
	git rm -rf a &&
	git commit -m "remove a" &&
	check_blame <<-\EOF
	1 file
	EOF
'

test_expect_success 'cross merge boundaries in blaming' '
	git checkout HEAD^0 &&
	git rm -rf . &&
	test_commit m1 &&
	git checkout HEAD^ &&
	git rm -rf . &&
	test_commit m2 &&
	git merge m1 &&
	check_blame <<-\EOF
	m1 m1.t
	m2 m2.t
	EOF
'

test_expect_success 'blame merge for resolved conflicts' '
	git checkout HEAD^0 &&
	git rm -rf . &&
	test_commit c1 conflict &&
	git checkout HEAD^ &&
	git rm -rf . &&
	test_commit c2 conflict &&
	test_must_fail git merge c1 &&
	test_commit resolved conflict &&
	check_blame conflict <<-\EOF
	resolved conflict
	EOF
'

test_done
