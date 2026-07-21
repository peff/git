#!/bin/sh

test_description='reflog timestamps around the Unix epoch'

GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME=main
export GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME

. ./test-lib.sh

for ref_format in files reftable
do
	test_expect_success "$ref_format reflogs support signed timestamps" '
		repo=$ref_format-repo &&
		test_when_finished "rm -rf $repo" &&
		git init --ref-format=$ref_format "$repo" &&
		test_commit -C "$repo" base &&
		base=$(git -C "$repo" rev-parse HEAD) &&

		negative=$(printf "%s\n" negative |
			git -C "$repo" commit-tree HEAD^{tree} -p HEAD) &&
		zero=$(printf "%s\n" zero |
			git -C "$repo" commit-tree HEAD^{tree} -p "$negative") &&
		GIT_COMMITTER_DATE="@-1 +0000" \
			git -C "$repo" update-ref -m negative \
			refs/heads/main "$negative" &&
		GIT_COMMITTER_DATE="@0 +0000" \
			git -C "$repo" update-ref -m zero \
			refs/heads/main "$zero" &&

		cat >expect <<-EOF &&
		refs/heads/main@{0 +0000}
		refs/heads/main@{-1 +0000}
		EOF
		git -C "$repo" reflog show -2 --date=raw --format=%gD \
			refs/heads/main >actual &&
		test_cmp expect actual &&

		printf "%s\n" "$zero" "$negative" "$base" >expect &&
		git -C "$repo" reflog expire --expire=never \
			--expire-unreachable=never refs/heads/main &&
		git -C "$repo" reflog show --format=%H refs/heads/main >actual &&
		test_cmp expect actual &&

		printf "%s\n" "$zero" "$base" >expect &&
		git -C "$repo" reflog expire --expire="@0 +0000" \
			--expire-unreachable=never refs/heads/main &&
		git -C "$repo" reflog show --format=%H refs/heads/main >actual &&
		test_cmp expect actual
	'

	test_expect_success "$ref_format reflog config preserves negative timestamps" '
		repo=$ref_format-config-repo &&
		test_when_finished "rm -rf $repo" &&
		git init --ref-format=$ref_format "$repo" &&
		test_commit -C "$repo" base &&

		negative=$(printf "%s\n" negative |
			git -C "$repo" commit-tree HEAD^{tree} -p HEAD) &&
		GIT_COMMITTER_DATE="@-1 +0000" \
			git -C "$repo" update-ref -m negative \
			refs/heads/main "$negative" &&
		git -C "$repo" config \
			"gc.refs/heads/main.reflogExpire" false &&
		git -C "$repo" reflog show --format=%H refs/heads/main >expect &&
		git -C "$repo" reflog expire refs/heads/main &&
		git -C "$repo" reflog show --format=%H refs/heads/main >actual &&
		test_cmp expect actual &&

		GIT_COMMITTER_DATE="@-2 +0000" \
			git -C "$repo" update-ref --create-reflog -m stash \
			refs/stash "$negative" &&
		git -C "$repo" reflog show --format=%H refs/stash >expect &&
		git -C "$repo" reflog expire refs/stash &&
		git -C "$repo" reflog show --format=%H refs/stash >actual &&
		test_cmp expect actual
	'
done

test_done
