MIX = mix
CNODE_CFLAGS = -g -O2 -std=c99 -pedantic -Wcomment -Wextra -Wno-old-style-declaration -Wall

# ignore unused parameter warnings
CNODE_CFLAGS += -Wno-unused-parameter

# set erlang include path
ERLANG_PATH = $(shell erl -eval 'io:format("~s", [lists:concat([code:root_dir(), "/erts-", erlang:system_info(version)])])' -s init stop -noshell)
CNODE_CFLAGS += -I$(ERLANG_PATH)/include

# expecting myhtml as a submodule in c_src/
# that way we can pin a version and package the whole thing in hex
# hex does not allow for non-app related dependencies.
MYHTML_PATH = c_src/myhtml
MYHTML_STATIC = $(MYHTML_PATH)/lib/libmyhtml_static.a
CNODE_CFLAGS += -I$(MYHTML_PATH)/include
# avoid undefined reference errors to phtread_mutex_trylock
CNODE_CFLAGS += -lpthread

# C-Node
ERL_INTERFACE = $(wildcard $(ERLANG_PATH)/../lib/erl_interface-*)
CNODE_CFLAGS += -L$(ERL_INTERFACE)/lib
CNODE_CFLAGS += -I$(ERL_INTERFACE)/include

CNODE_LDFLAGS =

ifeq ($(OTP22_DEF),YES)
  CNODE_CFLAGS += -DOTP_22_OR_NEWER
else
  CNODE_LDFLAGS += -lerl_interface
endif

CNODE_LDFLAGS += -lei -pthread

.PHONY: all

all: priv/myhtml_worker

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
