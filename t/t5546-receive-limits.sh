#!/bin/sh

test_description='check receive input limits'
. ./test-lib.sh

# Let's run tests with different unpack limits: 1 and 10000
# When the limit is 1, `git receive-pack` will call `git index-pack`.
# When the limit is 10000, `git receive-pack` will call `git unpack-objects`.

test_pack_input_limit () {
	case "$1" in
	index) unpack_limit=1 ;;
	unpack) unpack_limit=10000 ;;
	esac

	test_expect_success 'prepare destination repository' '
		rm -fr dest &&
		git --bare init dest
	'

	test_expect_success "set unpacklimit to $unpack_limit" '
		git --git-dir=dest config receive.unpacklimit "$unpack_limit"
	'

	test_expect_success 'setting receive.maxInputSize to 512 rejects push' '
		git --git-dir=dest config receive.maxInputSize 512 &&
		test_must_fail git push dest HEAD
	'

	test_expect_success 'bumping limit to 4k allows push' '
		git --git-dir=dest config receive.maxInputSize 4k &&
		git push dest HEAD
	'

	test_expect_success 'prepare destination repository (again)' '
		rm -fr dest &&
		git --bare init dest
	'

	test_expect_success 'lifting the limit allows push' '
		git --git-dir=dest config receive.maxInputSize 0 &&
		git push dest HEAD
	'
}

test_expect_success "create known-size (1024 bytes) commit" '
	test-tool genrandom foo 1024 >one-k &&
	git add one-k &&
	test_commit one-k
'

test_pack_input_limit index
test_pack_input_limit unpack

test_done

# XXX need to refactor
create_dest() {
	rm -rf dest &&
	git init --bare dest &&
	git --git-dir=dest config receive.unpacklimit 1
}

create_hook() {
	write_script dest/hooks/pre-receive <<-\EOF
	log="$GIT_QUARANTINE_PATH/.large-objects"
	test -s "$log" || exit 0

	tips=
	while read old new ref; do
		test "$new" = "$_z40" && continue
		tips="$tips $new"
	done

	echo >&2 "blocking push due to size"
	while read sha1 size; do
		path=$(git rev-list --find="$sha1" $tips)
		echo >&2 "too large ($size): ${path:-$sha1}"
	done <"$log"
	exit 1
	EOF
}

test_expect_success 'index-pack can warn about large object' '
	git pack-objects --all --stdout </dev/null >tmp.pack &&
	git index-pack --warn-object-size=512 --stdin <tmp.pack 2>stderr &&
	echo "large-object: $blob 1024" >expect &&
	test_cmp expect stderr
'

test_expect_success 'receive.warnobjectsize does not block large object' '
	create_dest &&
	git --git-dir=dest config receive.warnobjectsize 512 &&
	git push dest HEAD
'

test_expect_success 'receive.warnobjectsize writes log' '
	create_dest &&
	create_hook &&
	git --git-dir=dest config receive.warnobjectsize 512 &&
	test_must_fail git push dest HEAD 2>stderr
'

test_expect_success 'rejected push cleans up object' '
	(
		cd dest &&
		test_must_fail git cat-file -t $blob
	)
'

test_expect_success 'pre-receive hook parsed large-object log' '
	perl -lne "print \$1 if /remote: (.*?)\\s+\$/" stderr >actual &&
	cat >expect <<-EOF &&
	blocking push due to size
	too large (1024): $blob $commit/file
	EOF
	test_cmp expect actual
'

test_expect_success 'bumping limit allows push' '
	git --git-dir=dest config receive.warnobjectsize 4k &&
	git push dest HEAD
'

test_expect_success 'create delta-capable commit' '
	echo foo >>file &&
	git add file &&
	test_commit delta
'

test_expect_success 'warnobjectsize catches deltified objects' '
	create_dest &&
	create_hook &&
	git push dest HEAD^:refs/heads/master &&
	git --git-dir=dest config receive.maxsize 512 &&
	git --git-dir=dest config receive.warnobjectsize 512 &&
	test_must_fail git push dest HEAD &&
	git --git-dir=dest config receive.warnobjectsize 4k &&
	git push dest HEAD
'

test_done
