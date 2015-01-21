#!/bin/sh

# This is what it's called in the Debian package, but it seems
# like there ought to be a symlink without the version...
CFD=clang-format-diff-3.6

# Strip out --color, as clang's patch reader cannot handle it.
# Robustly handling arrays in bourne shell is insane.
eval "set -- $(
	for i in "$@"; do
		test "--color" = "$i" && continue
		printf " '"
		printf '%s' "$i" | sed "s/'/'\\\\''/g"
		printf "'"
	done
)"

git diff-index -p "$@" |
$CFD -p1 |
sed -e 's,^--- ,&a/,' -e 's,^+++ ,&b/,'
