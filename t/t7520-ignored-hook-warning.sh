#!/bin/sh

test_description='ignored hook warning'

TEST_PASSES_SANITIZE_LEAK=true
. ./test-lib.sh
. "$TEST_DIRECTORY"/lib-terminal.sh

test_expect_success setup '
	test_hook --setup pre-commit <<-\EOF
	exit 0
	EOF
'

test_expect_success 'no warning if hook is not ignored' '
	git commit --allow-empty -m "more" 2>message &&
	test_grep ! -e "hook was ignored" message
'

test_expect_success POSIXPERM 'warning if hook is ignored' '
	test_hook --disable pre-commit &&
	git commit --allow-empty -m "even more" 2>message &&
	test_grep -e "hook was ignored" message
'

test_expect_success POSIXPERM 'no warning if advice.ignoredHook set to false' '
	test_config advice.ignoredHook false &&
	test_hook --disable pre-commit &&
	git commit --allow-empty -m "even more" 2>message &&
	test_grep ! -e "hook was ignored" message
'

test_expect_success 'no warning if unset advice.ignoredHook and hook removed' '
	test_hook --remove pre-commit &&
	test_unconfig advice.ignoredHook &&
	git commit --allow-empty -m "even more" 2>message &&
	test_grep ! -e "hook was ignored" message
'

test_expect_success TTY,POSIXPERM 'push --quiet silences remote hook warnings' '
	git init --bare dst.git &&
	echo "exit 0" >dst.git/hooks/update &&
	chmod -x dst.git/hooks/update &&

	git commit --allow-empty -m one &&
	test_terminal git push dst.git HEAD 2>message &&
	grep -e "hook was ignored" message &&

	git commit --allow-empty -m two &&
	test_terminal git push --quiet dst.git HEAD 2>message &&
	! grep -e "hook was ignored" message
'

test_done
