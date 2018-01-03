#!/bin/sh

test_description='ignored hook warning'

. ./test-lib.sh
. "$TEST_DIRECTORY"/lib-terminal.sh

test_expect_success setup '
	hookdir="$(git rev-parse --git-dir)/hooks" &&
	hook="$hookdir/pre-commit" &&
	mkdir -p "$hookdir" &&
	write_script "$hook" <<-\EOF
	exit 0
	EOF
'

test_expect_success 'no warning if hook is not ignored' '
	git commit --allow-empty -m "more" 2>message &&
	test_i18ngrep ! -e "hook was ignored" message
'

test_expect_success POSIXPERM 'warning if hook is ignored' '
	chmod -x "$hook" &&
	git commit --allow-empty -m "even more" 2>message &&
	test_i18ngrep -e "hook was ignored" message
'

test_expect_success POSIXPERM 'no warning if advice.ignoredHook set to false' '
	test_config advice.ignoredHook false &&
	chmod -x "$hook" &&
	git commit --allow-empty -m "even more" 2>message &&
	test_i18ngrep ! -e "hook was ignored" message
'

test_expect_success 'no warning if unset advice.ignoredHook and hook removed' '
	rm -f "$hook" &&
	test_unconfig advice.ignoredHook &&
	git commit --allow-empty -m "even more" 2>message &&
	test_i18ngrep ! -e "hook was ignored" message
'

test_expect_success TTY,POSIXPERM 'push --quiet silences remote hook warnings' '
	git init --bare dst.git &&
	echo "exit 0" >dst.git/hooks/update &&
	chmod -x dst.git/hooks/update &&

	git commit --allow-empty -m one &&
	test_terminal git push dst.git HEAD 2>message &&
	test_i18ngrep -e "hook was ignored" message &&

	git commit --allow-empty -m two &&
	test_terminal git push --quiet dst.git HEAD 2>message &&
	test_i18ngrep ! -e "hook was ignored" message
'

test_done
