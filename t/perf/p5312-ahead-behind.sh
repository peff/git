#!/bin/sh

test_description='performance of ahead/behind calculations

This is most interesting on a repo with a reasonably large number of real topic
branches. E.g., a clone of gitster/git, with all of the git.git topic branches
in refs/remotes/origin.

We will check "git branch -v", which does ahead/behind for all branches, and
whose performance may change between git versions.

We will also compare doing N separate rev-list invocations versus the new
ahead/behind helper. This shows how much the helper is improving things even
within a single version.

We will also try with and without bitmaps to show their impact.
'
. ./perf-lib.sh

test_perf_default_repo

test_expect_success 'populate branches from origin/*' '
	git for-each-ref --format="%(refname:short)" refs/remotes/origin/ |
	while read remote; do
		test "$remote" = "origin/HEAD" && continue
		branch=${remote#origin/} &&
		git update-ref refs/heads/$branch $remote
	done
'

test_expect_success 'simulate tracked local branch for each remote branch' '
	git config remote.origin.url does-not-matter &&
	git config remote.origin.fetch "refs/heads/*:refs/remotes/origin/*" &&
	git for-each-ref --format="%(refname:short)" refs/heads/ |
	while read branch; do
		git config branch.$branch.remote origin &&
		git config branch.$branch.merge refs/heads/master
	done
'

test_expect_success 'remove any existing bitmaps' '
	rm -f .git/objects/pack/*.bitmap
'

run_timings () {
	test_perf "branch -v ($1)" '
		git branch -v
	'

	test_perf "rev-list ($1)" '
		git for-each-ref --format="%(refname:short)" refs/heads/ |
		head |
		(
			while read branch; do
				git rev-list --count --left-right \
					$branch@{upstream}...$branch || exit 1
			done
		)
	'

	test_perf "ahead-behind ($1)" '
		git for-each-ref --format="%(refname:short)" refs/heads/ |
		while read branch; do
			echo "$branch@{upstream}..$branch"
		done |
		git ahead-behind --stdin
	'
}

run_timings walker

test_expect_success 'turn on bitmaps' '
	git repack -adb
'

run_timings bitmap

test_done
