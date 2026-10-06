#!/bin/sh

test_description='provisional object formats for the first push'

. ./test-lib.sh

assert_settled () {
	if test -d "$1/.git"
	then
		config_file="$1/.git/config"
	else
		config_file="$1/config"
	fi &&
	test_must_fail git config get --file "$config_file" extensions.provisionalObjectFormat &&
	test "$(git -C "$1" rev-parse --show-object-format)" = "$2"
}

test_expect_success 'an ordinary command settles a manually configured empty repository' '
	git init --bare --ref-storage-format=files --object-format=sha1 manual &&
	git config --file manual/config core.repositoryFormatVersion 1 &&
	git config --file manual/config extensions.provisionalObjectFormat sha256 &&
	echo content | git -C manual hash-object -w --stdin >oid &&
	assert_settled manual sha1 &&
	git -C manual cat-file -e "$(cat oid)"
'


test_done
