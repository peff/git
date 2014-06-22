#!/bin/sh

test_description='speed of tag --contains lookups'
. ./perf-lib.sh

test_perf_default_repo

test_expect_success 'find reference points' '
	recent=$(git rev-list HEAD | head -500 | tail -n 1) &&
	old=$(git rev-list HEAD | head -15000 | tail -n 1) &&
	ancient=$(git rev-list HEAD | tail -n 1)
'

test_expect_success 'find most recent tag' '
	tag=$(git for-each-ref --sort=-taggerdate \
			       --format="%(refname:short)" \
			       refs/tags |
	      head -n 1)
'

for distance in recent old ancient; do
	contains=$(eval echo \$$distance)
	for match in "" "$tag"; do
		test_perf "contains $distance/${match:-all}" "
			git tag -l --contains $contains $match
		"
	done
done

test_done
