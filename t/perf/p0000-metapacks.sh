#!/bin/sh

test_description="Tests history walking performance with metapacks"

. ./perf-lib.sh

test_perf_default_repo

test_expect_success 'build metapacks' '
        rm -vf .git/objects/pack/*.commits
	# old versions do not have metapacks at all
	test_might_fail git metapack --all --commits
'

test_perf 'rev-list --all' '
	git rev-list --all >/dev/null
'

test_done
