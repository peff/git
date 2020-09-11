#!/bin/sh

test_description='index-pack --unpack'
. ./test-lib.sh

mktmp () {
	test_when_finished "rm -rf tmp" &&
	git init tmp
}

verify_objects () {
	git -C tmp rev-list --objects $head >actual &&
	test_cmp rev-list.expect actual
}

verify_packs () {
	ls tmp/.git/objects/pack >actual &&
	# expect pack and .idx
	test_line_count = $((2 * $1)) actual
}

test_expect_success 'create some objects' '
	test-tool genrandom foo 4096 >file &&
	git add . &&
	git commit -m one &&

	echo extra >>file &&
	git add . &&
	git commit -m two &&

	head=$(git rev-parse HEAD) &&
	git rev-list --objects HEAD >rev-list.expect
'

test_expect_success 'create some packs' '
	git pack-objects --all --stdout >ref-delta.pack &&
	git pack-objects --all --stdout --delta-base-offset >ofs-delta.pack &&

	git pack-objects --revs --stdout >base.pack <<-\EOF &&
	HEAD^
	EOF

	git pack-objects --revs --stdout --thin >thin.pack <<-\EOF
	HEAD
	--not
	HEAD^
	EOF
'

test_expect_success 'unpack ref-delta.pack' '
	mktmp &&
	git -C tmp index-pack --stdin --unpack <ref-delta.pack &&
	verify_objects &&
	verify_packs 0
'

test_expect_success 'unpack ofs-delta.pack' '
	mktmp &&
	git -C tmp index-pack --stdin --unpack <ofs-delta.pack &&
	verify_objects &&
	verify_packs 0
'

test_expect_success 'unpack base and thin packs' '
	mktmp &&
	git -C tmp index-pack --stdin --unpack <base.pack &&
	git -C tmp index-pack --stdin --unpack <thin.pack &&
	verify_objects &&
	verify_packs 0
'

test_expect_success 'unpack limit (under)' '
	mktmp &&
	git -C tmp index-pack --stdin --unpack-limit=10 <ofs-delta.pack &&
	verify_objects &&
	verify_packs 0
'

test_expect_success 'unpack limit (over)' '
	mktmp &&
	git -C tmp index-pack --stdin --unpack-limit=3 <ofs-delta.pack &&
	verify_objects &&
	verify_packs 1
'

test_done
