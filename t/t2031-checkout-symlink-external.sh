#!/bin/sh

test_description='detection and prevention of out-of-tree symlinks'
. ./test-lib.sh

if ! test_have_prereq SYMLINKS
then
	skip_all='skipping external symlink tests (missing SYMLINKS)'
	test_done
fi

create_symlink() {
	symlink=$1
	target=$2
	test_expect_success "create symlink ($symlink)" '
		sha1=$(printf "%s" "$target" | git hash-object -w --stdin) &&
		git update-index --add --cacheinfo "120000,$sha1,$symlink"
	'
}

check_symlink () {
	symlink=$1
	config=$2
	outcome=$3
	expect=$4

	if test "$outcome" = "allow"
	then
		fail=
		: ${expect:=test_cmp ../target}
	else
		fail=test_must_fail
		: ${expect:=! cat}
	fi

	test_expect_success " check symlink ($symlink, $config -> $outcome)" "
		rm -f $symlink &&
		$fail git -c core.allowExternalSymlinks=$config \\
			checkout-index -- $symlink &&
		$expect $symlink
	"
}

# we want to try breaking out of the repository,
# so let's work inside a sub-repository, and break
# out to the top-level trash directory
test_expect_success 'set up repository' '
	echo content >target &&
	git init subrepo &&
	cd subrepo &&
	test_commit base &&
	echo content >in-repo-target
'

create_symlink in-repo in-repo-target
check_symlink in-repo false allow

create_symlink subdir/in-repo ../in-repo-target
check_symlink subdir/in-repo false allow

create_symlink absolute "$TRASH_DIRECTORY/target"
check_symlink absolute true allow
check_symlink absolute false forbid

create_symlink relative "../target"
check_symlink relative true allow
check_symlink relative false forbid

create_symlink curdir .
check_symlink curdir false allow test_path_is_dir
create_symlink sneaky curdir/../target
check_symlink sneaky true allow
check_symlink sneaky false forbid

test_expect_success 'applying a patch checks symlink config' '
	git diff-index -p --cached HEAD -- relative >patch &&
	rm -f relative &&
	git -c core.allowExternalSymlinks=true apply <patch &&
	test_cmp ../target relative &&
	rm -f relative &&
	test_must_fail git -c core.allowExternalSymlinks=false apply <patch
'

test_expect_success 'merge-recursive checks symlinks config' '
	git reset --hard &&

	# create rename situation which requires processing
	# outside of unpack_trees()
	ln -s ../foo one &&
	git add one &&
	git commit -m base &&

	ln -sf ../target one &&
	git commit -am modify &&

	git checkout -b side HEAD^ &&
	git mv one two &&
	git commit -am rename &&

	git -c core.allowExternalSymlinks=true merge master &&
	test_cmp ../target two &&

	git reset --hard HEAD^ &&
	test_must_fail git -c core.allowExternalSymlinks=false merge master
'

test_done
