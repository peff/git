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

other_format () {
	case "$1" in
	sha1) echo sha256 ;;
	sha256) echo sha1 ;;
	esac
}

push_status () {
	if git -C "$1" push "$2" "$3" >"$4.out" 2>&1
	then
		echo success >"$4.status"
	else
		echo failure >"$4.status"
	fi
}

test_expect_success 'an ordinary command settles a manually configured empty repository' '
	git init --bare --ref-storage-format=files --object-format=sha1 manual &&
	git config --file manual/config core.repositoryFormatVersion 1 &&
	git config --file manual/config extensions.provisionalObjectFormat sha256 &&
	echo content | git -C manual hash-object -w --stdin >oid &&
	assert_settled manual sha1 &&
	git -C manual cat-file -e "$(cat oid)"
'

test_expect_success 'setup sources for both algorithms' '
	git init --object-format=sha1 sha1 &&
	git init --object-format=sha256 sha256 &&
	test_commit -C sha1 one &&
	test_commit -C sha256 two
'

for refs in files reftable
do
	for default in sha1 sha256
	do
		for incoming in sha1 sha256
		do
			test_expect_success "$refs: $default accepts first $incoming push" '
				target=$refs-$default-$incoming &&
				git init --bare --ref-storage-format=$refs \
					--object-format=$default --provisional-object-format="$(other_format "$default")" "$target" &&
				assert_provisional "$target" &&
				git receive-pack --advertise-refs "$target" >advertisement &&
				test_grep "provisional-object-format=" advertisement &&
				git ls-remote "$target" &&
				assert_provisional "$target" &&
				git -C "$incoming" push "../$target" HEAD:refs/heads/main &&
				assert_settled "$target" "$incoming" &&
				git -C "$target" fsck &&
				git -C "$incoming" rev-parse HEAD >expect &&
				git -C "$target" rev-parse refs/heads/main >actual &&
				test_cmp expect actual
			'
		done
	done

	test_expect_success "$refs: object write settles default" '
		git init --bare --ref-storage-format=$refs --object-format=sha1 \
			--provisional-object-format=sha256 "$refs-object" &&
		echo content | git -C "$refs-object" hash-object -w --stdin &&
		assert_settled "$refs-object" sha1
	'

	test_expect_success "$refs: empty index write settles default" '
		git init --ref-storage-format=$refs --object-format=sha256 \
			--provisional-object-format=sha1 "$refs-index" &&
		git -C "$refs-index" read-tree --empty &&
		assert_settled "$refs-index" sha256 &&
		git -C "$refs-index" ls-files --stage
	'

	test_expect_success "$refs: symref write settles default" '
		git init --bare --ref-storage-format=$refs --object-format=sha1 \
			--provisional-object-format=sha256 "$refs-symref" &&
		git -C "$refs-symref" symbolic-ref HEAD refs/heads/other &&
		assert_settled "$refs-symref" sha1
	'

	test_expect_success "$refs: rejected push still settles selected format" '
		git init --bare --ref-storage-format=$refs --object-format=sha1 \
			--provisional-object-format=sha256 "$refs-reject" &&
		write_script "$refs-reject/hooks/pre-receive" <<-\EOF &&
		exit 1
		EOF
		test_must_fail git -C sha256 push "../$refs-reject" HEAD:refs/heads/main &&
		assert_settled "$refs-reject" sha256 &&
		test_must_fail git -C "$refs-reject" show-ref --verify refs/heads/main
	'
done

test_expect_success 'cannot opt an existing repository into provisional formats' '
	test_must_fail git -C sha1 init --provisional-object-format=sha256 &&
	assert_settled sha1 sha1
'

for chosen in sha1 sha256
do
	test_expect_success "recover interrupted reftable conversion by choosing $chosen" '
		target=recover-$chosen &&
		git init --bare --ref-storage-format=reftable --object-format=sha1 \
			--provisional-object-format=sha256 --initial-branch=master "$target" &&
		test-tool repository rewrite-object-format "$target" sha256 &&
		assert_provisional "$target" &&
		echo refs/heads/master >before &&
		git receive-pack --advertise-refs "$target" >advertisement &&
		assert_provisional "$target" &&
		git -C "$chosen" push "../$target" HEAD:refs/heads/main &&
		assert_settled "$target" "$chosen" &&
		git -C "$target" symbolic-ref HEAD >after &&
		test_cmp before after &&
		git -C "$target" fsck
	'
done

test_expect_success 'conversion rejects physical OIDs hidden by a symref' '
	git init --bare --ref-storage-format=reftable --object-format=sha1 physical &&
	oid=$(echo content | git -C physical hash-object -w --stdin) &&
	GIT_TEST_REFTABLE_AUTOCOMPACTION=0 git -C physical update-ref refs/hidden "$oid" &&
	GIT_TEST_REFTABLE_AUTOCOMPACTION=0 git -C physical symbolic-ref refs/hidden refs/missing &&
	git config --file physical/config extensions.provisionalObjectFormat sha256 &&
	cp physical/reftable/tables.list before &&
	test_must_fail git -C sha256 push ../physical HEAD:refs/heads/main &&
	assert_provisional physical &&
	test_cmp before physical/reftable/tables.list &&
	git config unset --file physical/config extensions.provisionalObjectFormat &&
	git -C physical cat-file -e "$oid"
'

test_expect_success 'conversion rejects physical tombstones' '
	git init --bare --ref-storage-format=reftable --object-format=sha1 tombstone &&
	git -C tombstone symbolic-ref refs/gone refs/missing &&
	GIT_TEST_REFTABLE_AUTOCOMPACTION=0 git -C tombstone symbolic-ref --delete refs/gone &&
	git config --file tombstone/config extensions.provisionalObjectFormat sha256 &&
	cp tombstone/reftable/tables.list before &&
	test_must_fail git -C sha256 push ../tombstone HEAD:refs/heads/main &&
	test_cmp before tombstone/reftable/tables.list
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

test_expect_success 'conversion rejects a reflog with null object IDs' '
	git init --bare --ref-storage-format=reftable --object-format=sha1 log-only &&
	(
		cd log-only &&
		test-tool ref-store main create-reflog refs/heads/main
	) &&
	git config --file log-only/config extensions.provisionalObjectFormat sha256 &&
	cp log-only/reftable/tables.list before &&
	test_must_fail git -C sha256 push ../log-only HEAD:refs/heads/main &&
	test_cmp before log-only/reftable/tables.list
'

test_expect_success 'shallow push uses the selected alternative hash' '
	git clone --depth=1 "file://$PWD/sha256" shallow-source &&
	git init --bare --ref-storage-format=reftable --object-format=sha1 \
		--provisional-object-format=sha256 shallow-target &&
	git config --file shallow-target/config receive.shallowUpdate true &&
	git -C shallow-source push ../shallow-target HEAD:refs/heads/main &&
	assert_settled shallow-target sha256 &&
	git -C shallow-target fsck
'

test_expect_success 'legacy push without object-format capability selects SHA-1' '
	git init --bare --ref-storage-format=reftable --object-format=sha1 \
		--provisional-object-format=sha256 legacy &&
	git -C sha1 pack-objects --stdout --all >pack &&
	{
		packetize "$(test_oid --hash=sha1 zero) $(git -C sha1 rev-parse HEAD) refs/heads/main" &&
		printf 0000 &&
		cat pack
	} >request &&
	git receive-pack legacy <request >response &&
	assert_settled legacy sha1 &&
	git -C legacy fsck
'

test_expect_success 'reference tracing works through conversion' '
	git init --bare --ref-storage-format=reftable --object-format=sha1 \
		--provisional-object-format=sha256 traced &&
	GIT_TRACE_REFS=1 git -C sha256 push ../traced HEAD:refs/heads/main 2>trace &&
	assert_settled traced sha256 &&
	git -C traced fsck
'

test_expect_success 'provisional initialization rejects objects seeded by templates' '
	mkdir template-objects &&
	cp -R sha1/.git/objects template-objects/ &&
	test_must_fail git init --object-format=sha1 --provisional-object-format=sha256 \
		--template=template-objects seeded-objects 2>err &&
	test_grep "existing object data" err &&
	assert_settled seeded-objects sha1 &&
	git -C seeded-objects cat-file -e "$(git -C sha1 rev-parse HEAD)"
'

test_expect_success 'provisional initialization rejects an index seeded by templates' '
	git init --object-format=sha1 index-source &&
	git -C index-source read-tree --empty &&
	mkdir template-index &&
	cp index-source/.git/index template-index/ &&
	test_must_fail git init --object-format=sha1 --provisional-object-format=sha256 \
		--template=template-index seeded-index 2>err &&
	test_grep "existing metadata" err &&
	assert_settled seeded-index sha1
'

test_expect_success 'provisional initialization rejects direct refs seeded by templates' '
	mkdir -p template-refs/refs/heads &&
	git -C sha1 rev-parse HEAD >template-refs/refs/heads/main &&
	test_must_fail git init --ref-storage-format=files --object-format=sha1 \
		--provisional-object-format=sha256 --template=template-refs seeded-refs 2>err &&
	test_grep "hash-dependent refs" err &&
	assert_settled seeded-refs sha1
'

test_expect_success 'a dry-run push leaves provisional formats intact' '
	git init --bare --object-format=sha1 --provisional-object-format=sha256 dry-run &&
	git -C sha256 push --dry-run ../dry-run HEAD:refs/heads/main &&
	assert_provisional dry-run
'

test_expect_success 'index-pack settles before importing a pack' '
	git init --bare --ref-storage-format=reftable --object-format=sha1 \
		--provisional-object-format=sha256 packed &&
	git -C sha1 pack-objects --stdout --all >pack &&
	git -C packed index-pack --stdin <pack &&
	assert_settled packed sha1 &&
	git -C packed cat-file -e "$(git -C sha1 rev-parse HEAD)" &&
	git -C packed fsck
'

test_expect_success 'adding a linked worktree settles the main repository first' '
	git init --bare --ref-storage-format=reftable --object-format=sha256 \
		--provisional-object-format=sha1 worktree-main &&
	git -C worktree-main worktree add --orphan ../worktree-linked &&
	assert_settled worktree-main sha256 &&
	assert_settled worktree-linked sha256
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

test_expect_success 'repeatable provisional formats are advertised and removed together' '
	git init --bare --object-format=sha1 --provisional-object-format=sha1 \
		--provisional-object-format=sha256 --provisional-object-format=sha256 choices &&
	printf "sha1\nsha256\n" >expect &&
	git config get --file choices/config --all extensions.provisionalObjectFormat >actual &&
	test_cmp expect actual &&
	git receive-pack --advertise-refs choices >advertisement &&
	test_grep "provisional-object-format=sha1" advertisement &&
	test_grep "provisional-object-format=sha256" advertisement &&
	git -C sha256 push ../choices HEAD:refs/heads/main &&
	assert_settled choices sha256 &&
	git -C choices fsck
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

for refs in files reftable
do
	test_expect_success "$refs: clone, commit and push into a provisional repository" '
		target=clone-$refs &&
		git init --bare --ref-storage-format=$refs --object-format=sha1 \
			--provisional-object-format=sha256 "$target" &&
		git clone "file://$PWD/$target" "$target-client" &&
		assert_provisional "$target" &&
		test_commit -C "$target-client" initial &&
		git -C "$target-client" push origin HEAD:refs/heads/main &&
		assert_settled "$target" sha1 &&
		git -C "$target" fsck
	'
done

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
