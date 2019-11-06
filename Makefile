MIX = mix
MYHTML_WORKER_CFLAGS = -g -O2 -std=c99 -pedantic -Wcomment -Wextra -Wno-old-style-declaration -Wall
# we need to compile position independent code
MYHTML_WORKER_CFLAGS += -fpic -DPIC
# For some reason __erl_errno is undefined unless _REENTRANT is defined
MYHTML_WORKER_CFLAGS += -D_REENTRANT
# myhtmlex is using stpcpy, as defined in gnu string.h
# MYHTML_WORKER_CFLAGS += -D_GNU_SOURCE
# base on the same posix c source as myhtml
# MYHTML_WORKER_CFLAGS += -D_POSIX_C_SOURCE=199309
# turn warnings into errors
# MYHTML_WORKER_CFLAGS += -Werror
# ignore unused variables
# MYHTML_WORKER_CFLAGS += -Wno-unused-variable
# ignore unused parameter warnings
MYHTML_WORKER_CFLAGS += -Wno-unused-parameter

# set erlang include path
ERLANG_PATH = $(shell erl -eval 'io:format("~s", [lists:concat([code:root_dir(), "/erts-", erlang:system_info(version)])])' -s init stop -noshell)
MYHTML_WORKER_CFLAGS += -I$(ERLANG_PATH)/include

# expecting myhtml as a submodule in c_src/
# that way we can pin a version and package the whole thing in hex
# hex does not allow for non-app related dependencies.
MYHTML_PATH = c_src/myhtml
MYHTML_STATIC = $(MYHTML_PATH)/lib/libmyhtml_static.a
MYHTML_WORKER_CFLAGS += -I$(MYHTML_PATH)/include
# avoid undefined reference errors to phtread_mutex_trylock
MYHTML_WORKER_CFLAGS += -lpthread

# that would be used for a dynamically linked build
# MYHTML_WORKER_CFLAGS += -L$(MYHTML_PATH)/lib

MYHTML_WORKER_LDFLAGS = -shared

# C-Node
ERL_INTERFACE = $(wildcard $(ERLANG_PATH)/../lib/erl_interface-*)
CNODE_CFLAGS = $(MYHTML_WORKER_CFLAGS)
CNODE_CFLAGS += -L$(ERL_INTERFACE)/lib
CNODE_CFLAGS += -I$(ERL_INTERFACE)/include

CNODE_LDFLAGS =

ifeq ($(OTP22_DEF),YES)
  CNODE_CFLAGS += -DOTP_22_OR_NEWER
else
  CNODE_LDFLAGS += -lerl_interface
endif

CNODE_LDFLAGS += -lei -pthread

# enumerate docker build tests
BUILD_TESTS := $(patsubst %.dockerfile, %.dockerfile.PHONY, $(wildcard ./build-test/*.dockerfile))

# platform specific environment
UNAME = $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
    MYHTML_WORKER_LDFLAGS += -dynamiclib -undefined dynamic_lookup
else
    # myhtmlex is using stpcpy, as defined in gnu string.h
    MYHTML_WORKER_CFLAGS += -D_GNU_SOURCE
    # base on the same posix c source as myhtml
    # MYHTML_WORKER_CFLAGS += -D_POSIX_C_SOURCE=199309
endif

.PHONY: all

all: myhtmlex

myhtmlex: priv/myhtml_worker
	$(MIX) compile

$(MYHTML_STATIC): $(MYHTML_PATH)
	$(MAKE) -C $(MYHTML_PATH) library MyCORE_BUILD_WITHOUT_THREADS=YES

priv/myhtml_worker: c_src/myhtml_worker.c $(MYHTML_STATIC)
	$(CC) -o $@ $< $(MYHTML_STATIC) $(CNODE_CFLAGS) $(CNODE_LDFLAGS)

clean: clean-myhtml
	$(RM) -r priv/myhtmlex*
	$(RM) priv/myhtml_worker
	$(RM) myhtmlex-*.tar
	$(RM) -r package-test

clean-myhtml:
	$(MAKE) -C $(MYHTML_PATH) clean

# publishing the package and docs separately is required
# otherwise the build artifacts are included in the package
# and the tarball gets too big to be published
publish: clean
	$(MIX) hex.publish package
	$(MIX) hex.publish docs

test:
	$(MIX) test

build-tests: test $(BUILD_TESTS)

%.dockerfile.PHONY: %.dockerfile
	docker build -f $< .

