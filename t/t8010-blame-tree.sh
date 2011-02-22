#!/bin/sh

test_description='basic blame-tree tests'
. ./test-lib.sh

test_expect_success 'setup' '
	test_commit 1 file &&
	mkdir sub &&
	test_commit 2 sub/file &&
	mkdir -p deep/sub/nesting &&
	test_commit 3 deep/sub/nesting/file
'

cat >expect.root <<'EOF'
1 file
2 sub
3 deep
EOF

echo 2 file >expect.sub
echo 3 sub >expect.deep
echo 3 nesting >expect.deep.sub
echo 3 file >expect.deep.sub.nesting

check() {
	expect=$1; shift
	git blame-tree "$@" >actual &&
	git name-rev --stdin --name-only --tags <actual >tmp &&
	mv tmp actual &&
	tr '\t' ' ' <actual >tmp &&
	mv tmp actual &&
	sort <actual >tmp &&
	mv tmp actual &&
	test_cmp "$expect" actual
}

test_expect_success 'blame root' '
	check expect.root . HEAD
'

test_expect_success 'blame subdir' '
	check expect.sub sub HEAD
'

test_expect_success 'blame nested subdirs' '
	check expect.deep deep HEAD &&
	check expect.deep.sub deep/sub HEAD &&
	check expect.deep.sub.nesting deep/sub/nesting
'

test_expect_success 'assume HEAD if no rev opts' '
	check expect.root .
'

test_expect_success 'assume root if no path opt' '
	check expect.root
'

test_expect_success 'blame from older revision' '
	echo 1 file >expect &&
	check expect . HEAD~2
'

test_expect_success 'rev limiting works' '
	echo 3 deep >expect &&
	check expect . -1
'

test_expect_success 'complaint about a bogus path' '
	test_must_fail git blame-tree bogus HEAD
'

test_expect_success 'complain about a non-tree' '
	test_must_fail git blame-tree file HEAD
'

test_expect_success 'blame from subdir defaults to root' '
	(cd deep &&
	 check ../expect.root
	)
'

test_expect_success 'blame from subdir uses relative paths' '
	(cd deep &&
	 check ../expect.deep . &&
	 check ../expect.deep.sub sub
	)
'

test_done
