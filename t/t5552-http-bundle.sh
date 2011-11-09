#!/bin/sh

test_description='test fetching from http-accessible bundles'
. ./test-lib.sh

LIB_HTTPD_PORT=${LIB_HTTPD_PORT-'5552'}
. "$TEST_DIRECTORY"/lib-httpd.sh
start_httpd

test_expect_success 'create bundles' '
	test_commit one &&
	git bundle create "$HTTPD_DOCUMENT_ROOT_PATH/one.bundle" --all &&
	test_commit two &&
	git bundle create "$HTTPD_DOCUMENT_ROOT_PATH/two.bundle" --all ^one
'

test_expect_success 'clone from bundle' '
	git clone --bare $HTTPD_URL/one.bundle clone &&
	echo one >expect &&
	git --git-dir=clone log -1 --format=%s >actual &&
	test_cmp expect actual
'

test_expect_success 'fetch from bundle' '
	git --git-dir=clone fetch $HTTPD_URL/two.bundle refs/*:refs/* &&
	echo two >expect &&
	git --git-dir=clone log -1 --format=%s >actual &&
	test_cmp expect actual
'

test_expect_success 'cannot clone from partial bundle' '
	test_must_fail git clone $HTTPD_URL/two.bundle
'

stop_httpd
test_done
