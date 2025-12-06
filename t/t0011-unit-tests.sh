#!/bin/sh

test_description='run clar unit tests'
test_external=t
. ./test-lib.sh

# ugh, gross meson vs make difference
if test -d "$GIT_BUILD_DIR/t/unit-tests"
then
        UNIT_TESTS="$GIT_BUILD_DIR/t/unit-tests/bin/unit-tests"
else
        UNIT_TESTS="$GIT_BUILD_DIR/t/unit-tests"
fi

"$UNIT_TESTS" ${immediate:+-i} ||
  error "unit-test binary failed"

test_done
