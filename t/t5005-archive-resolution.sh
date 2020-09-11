#!/bin/sh

test_description='test object resolution methods for local and remote archive'
. ./test-lib.sh

test_expect_success 'setup' '
	echo one >one && git add one && git commit -m one &&
	sha1_referenced=`git rev-parse HEAD` &&
	git tag tagged &&
	echo two >two && git add two && git commit -m two &&
	sha1_unreferenced=`git rev-parse HEAD` &&
	git reset --hard HEAD^ &&
	echo three >three && git add three && git commit -m three &&
	git tag tagged-tree HEAD^{tree} &&
	git reset --hard HEAD^ &&
	mkdir subdir &&
	echo four >subdir/four && git add subdir && git commit -m four &&
	sha1_subtree=`git rev-parse HEAD:subdir`
'

# check that archiving $what from $where produces expected paths
check() {
	desc=$1; shift; # human-readable description
	where=$1; shift; # local|remote
	what=$1; shift; # the commit/tree id
	expect="$*"; # expected paths or "deny"

	cmd="git archive --format=tar -o result.tar"
	test "$where" = "remote" && cmd="$cmd --remote=."
	cmd="$cmd $what"

	if test "$expect" = "deny"; then
		test_expect_success "archive $desc ($where, should deny)" "
			test_must_fail $cmd
		"
	else
		test_expect_success "archive $desc ($where, should work)" '
			'"$cmd"' &&
			for i in '"$expect"'; do
				echo "$i:`basename $i`"
			done >expect &&
			rm -rf result &&
			mkdir result &&
			(cd result &&
			tar xf ../result.tar &&
			for i in `find * -type f -print`; do
				echo "$i:`cat $i`"
			done >../actual
			) &&
			test_cmp expect actual
		'
	fi
}

check 'ref'  local master one subdir/four
check 'ref' remote master one subdir/four

check 'relative ref'  local master^ one
check 'relative ref' remote master^ one

check 'reachable sha1'  local $sha1_referenced one
check 'reachable sha1' remote $sha1_referenced one

check 'unreachable sha1'  local $sha1_unreferenced one two
check 'unreachable sha1' remote $sha1_unreferenced deny

check 'reachable reflog'  local master@{0} one subdir/four
check 'reachable reflog' remote master@{0} one subdir/four

check 'unreachable reflog'  local master@{4} one two
check 'unreachable reflog' remote master@{4} deny

check 'tree via ref^{tree}'  local master^{tree} one subdir/four
check 'tree via ref^{tree}' remote master^{tree} one subdir/four

check 'tree via ref:'  local master: one subdir/four
check 'tree via ref:' remote master: one subdir/four

check 'subtree via ref:sub'  local master:subdir four
check 'subtree via ref:sub' remote master:subdir four

check 'subtree via sha1'  local $sha1_subtree four
check 'subtree via sha1' remote $sha1_subtree four

check 'tagged commit'  local tagged one
check 'tagged commit' remote tagged one

check 'tagged tree'  local tagged-tree one three
check 'tagged tree' remote tagged-tree one three

test_done
