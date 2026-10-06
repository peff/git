#!/bin/sh

test_description='provisional object formats for the first push'

. ./test-lib.sh

assert_provisional () {
	git config get --file "$1/config" --all extensions.provisionalObjectFormat >formats &&
	test_file_not_empty formats
}

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

test_expect_success 'a command doing its own setup settles even without writing' '
	git init --bare --object-format=sha1 --provisional-object-format=sha256 hash-only &&
	echo content | git -C hash-only hash-object --stdin &&
	assert_settled hash-only sha1
'

test_expect_success 'reinitialization preserves provisional formats and repository version' '
	git init --bare --ref-storage-format=files --object-format=sha1 \
		--provisional-object-format=sha256 reinit &&
	git -C reinit init --bare &&
	assert_provisional reinit &&
	test "$(git config --file reinit/config core.repositoryFormatVersion)" = 1
'

test_expect_success 'provisional formats require repository format version 1' '
	git init --bare --ref-storage-format=files --object-format=sha1 \
		--provisional-object-format=sha256 version-zero &&
	git config --file version-zero/config core.repositoryFormatVersion 0 &&
	test_must_fail git -C version-zero rev-parse --git-dir 2>err &&
	test_grep "v1-only extension" err
'

test_expect_success 'provisional formats cannot be combined with a compatibility object format' '
	git init --bare --object-format=sha1 --provisional-object-format=sha256 compat &&
	git config --file compat/config extensions.compatObjectFormat sha256 &&
	test_must_fail git -C compat rev-parse --git-dir 2>err &&
	test_grep "incompatible with compatObjectFormat" err
'

test_expect_success 'provisional formats do not select the default format' '
	GIT_DEFAULT_HASH=sha1 git init --bare --provisional-object-format=sha256 independent &&
	test "$(git config get --file independent/config --default=sha1 extensions.objectFormat)" = sha1 &&
	assert_provisional independent &&
	echo local | git -C independent hash-object -w --stdin &&
	assert_settled independent sha1
'

test_expect_success 'unknown provisional format is rejected before initialization' '
	test_must_fail git init --provisional-object-format=unknown invalid-format 2>err &&
	test_grep "unknown provisional object format" err &&
	test_path_is_missing invalid-format
'

test_expect_success 'each provisional format requires its own option' '
	test_must_fail git init --provisional-object-format=sha1,sha256 invalid-list 2>err &&
	test_grep "unknown provisional object format" err &&
	test_path_is_missing invalid-list
'

test_expect_success 'discovery rejects an unknown provisional format in the extension' '
	git init --bare --object-format=sha1 invalid-extension &&
	git config --file invalid-extension/config core.repositoryFormatVersion 1 &&
	git config --file invalid-extension/config extensions.provisionalObjectFormat unknown &&
	test_must_fail git -C invalid-extension rev-parse --git-dir 2>err &&
	test_grep "invalid value" err
'

test_expect_success 'ordinary read commands conservatively settle the format' '
	git init --bare --object-format=sha1 --provisional-object-format=sha256 read-command &&
	git -C read-command count-objects &&
	assert_settled read-command sha1
'

test_expect_success 'fetch settles before attempting to contact the remote' '
	git init --bare --object-format=sha1 --provisional-object-format=sha256 fetch-command &&
	test_must_fail git -C fetch-command fetch ../missing-remote &&
	assert_settled fetch-command sha1
'

for command in "rev-parse --git-dir" "symbolic-ref HEAD" "for-each-ref" \
	"show-ref --head" "config get core.repositoryFormatVersion"
do
	test_expect_success "$command settles the default format" '
		target=inspect-${command%% *} &&
		git init --bare --object-format=sha1 \
			--provisional-object-format=sha256 "$target" &&
		case "$command" in
		show-ref*) test_expect_code 1 git -C "$target" $command ;;
		*) git -C "$target" $command ;;
		esac &&
		assert_settled "$target" sha1
	'
done

test_done
