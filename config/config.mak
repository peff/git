Meta = $(HOME)/compile/git/Meta
ifeq ($(GIT_VERSION),omitted)
prefix := /none
else
prefix_base := $(shell $(Meta)/install/prefix)
ifeq ($(prefix_base), detached)
prefix := /do/not/install
else
prefix := $(HOME)/local/git/$(prefix_base)
endif
endif

CFLAGS =

COMPILER ?= gcc
O = 0
CC = ccache $(COMPILER)
export CCACHE_CPP2=1
CFLAGS += -g -O$(O)
CFLAGS += -Wall
LDFLAGS = -g

# Relax compilation on a detached HEAD (which is probably
# historical, and may contain compiler warnings that later
# got fixed).
head := $(shell git symbolic-ref HEAD 2>/dev/null)
rebasing := $(shell test -d "`git rev-parse --git-dir`/"rebase-* && echo yes)
private := $(shell grep -sq Meta/private "`git rev-parse --git-dir`/continue" && echo yes)
strict = $(or $(rebasing), $(head), $(private))
ifeq ($(strict),)
  CFLAGS += -Wno-error
  CFLAGS += -Wno-cpp
imap-send.o: EXTRA_CPPFLAGS += -DNO_OPENSSL
else
  DEVELOPER = 1
endif
ifeq ($(filter-out %maint, $(head)),)
  CFLAGS += -Wno-unused-value -Wno-strict-prototypes
endif

USE_LIBPCRE2 = YesPlease

GIT_TEST_OPTS = --root=/var/ram/git-tests -x --verbose-log
GIT_PROVE_OPTS= -j32 --state=slow,save
DEFAULT_TEST_TARGET = prove
export GIT_TEST_HTTPD = Yes
export GIT_TEST_GIT_DAEMON = Yes

GNU_ROFF = Yes

NO_GETTEXT = Nope
NO_TCLTK = Nope

GIT_PERF_MAKE_OPTS = O=2 strict= -j16
GIT_INTEROP_MAKE_OPTS = NO_OPENSSL=Nope strict= -j16

SPATCH_BATCH_SIZE = 8

CFLAGS += $(EXTRA_CFLAGS)

-include $(Meta)/config/config.mak.local
