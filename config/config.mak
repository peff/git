Meta = $(HOME)/compile/git/Meta
prefix_base := $(shell $(Meta)/install/prefix)
ifeq ($(prefix_base), detached)
prefix := /do/not/install
else
prefix := $(HOME)/local/git/$(prefix_base)
endif

CFLAGS =

ifdef SANITIZE
COMPILER ?= clang
CFLAGS += -fsanitize=$(SANITIZE) -fno-sanitize-recover=$(SANITIZE)
CFLAGS += -fno-omit-frame-pointer
ifeq ($(SANITIZE),memory)
CFLAGS += -fsanitize-memory-track-origins
endif
ifeq ($(SANITIZE),undefined)
INTERNAL_QSORT = YesPlease
CFLAGS += -DNO_UNALIGNED_LOADS
endif
endif

COMPILER ?= gcc
O = 0
CC = ccache $(COMPILER)
export CCACHE_CPP2=1
CFLAGS += -g -O$(O)
CFLAGS += -Wall -Werror
CFLAGS += -Wdeclaration-after-statement
CFLAGS += -Wpointer-arith
CFLAGS += -Wstrict-prototypes
CFLAGS += -Wvla
ifeq ($(patsubst clang-%,clang,$(COMPILER)), clang)
CFLAGS += -Wtautological-constant-out-of-range-compare
else
CFLAGS += -Wold-style-declaration
CFLAGS += -Wold-style-definition
endif
LDFLAGS = -g

# Relax compilation on a detached HEAD (which is probably
# historical, and may contain compiler warnings that later
# got fixed).
head = $(shell git symbolic-ref HEAD 2>/dev/null)
rebasing = $(shell test -d "`git rev-parse --git-dir`/"rebase-* && echo yes)
private = $(shell grep -sq Meta/private "`git rev-parse --git-dir`/continue" && echo yes)
strict = $(or $(rebasing), $(head), $(private))
ifeq ($(strict),)
  CFLAGS += -Wno-error
  CFLAGS += -Wno-cpp
  NO_OPENSSL = NotForOldBuilds
endif
ifeq ($(filter-out %maint, $(head)),)
  CFLAGS += -Wno-unused-value -Wno-strict-prototypes
endif

USE_LIBPCRE = YesPlease

GIT_TEST_OPTS = --root=/var/ram/git-tests
TEST_LINT = test-lint
GIT_PROVE_OPTS= -j16 --state=slow,save
DEFAULT_TEST_TARGET = prove
export GIT_TEST_HTTPD = Yes
export GIT_TEST_GIT_DAEMON = Yes

GNU_ROFF = Yes
MAN_BOLD_LITERAL = Yes

NO_GETTEXT = Nope
NO_TCLTK = Nope
XDL_FAST_HASH =

GIT_PERF_MAKE_OPTS = O=2 strict= -j16

CFLAGS += $(EXTRA_CFLAGS)

-include $(Meta)/config/config.mak.local
