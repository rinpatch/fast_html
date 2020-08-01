MIX = mix
CMAKE = cmake
CNODE_CFLAGS = -g -O2 -std=c99 -pedantic -Wcomment -Wextra -Wno-old-style-declaration -Wall

# ignore unused parameter warnings
CNODE_CFLAGS += -Wno-unused-parameter

# set erlang include path
ERLANG_PATH = $(shell erl -eval 'io:format("~s", [lists:concat([code:root_dir(), "/erts-", erlang:system_info(version)])])' -s init stop -noshell)
CNODE_CFLAGS += -I$(ERLANG_PATH)/include

# expecting myhtml as a submodule in c_src/
# that way we can pin a version and package the whole thing in hex
# hex does not allow for non-app related dependencies.
LXB_PATH = c_src/lexbor
LXB_STATIC = $(LXB_PATH)/liblexbor_static.a
CNODE_CFLAGS += -I$(LXB_PATH)/source
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

all: priv/fasthtml_worker

$(LXB_STATIC): $(LXB_PATH)
	# Sadly, build components separately seems to sporadically fail
	cd $(LXB_PATH); cmake -DLEXBOR_BUILD_SEPARATELY=OFF -DLEXBOR_BUILD_SHARED=OFF
	$(MAKE) -C $(LXB_PATH)

priv/fasthtml_worker: c_src/fasthtml_worker.c $(LXB_STATIC)
	$(CC) -o $@ $< $(LXB_STATIC) $(CNODE_CFLAGS) $(CNODE_LDFLAGS)

clean: clean-myhtml
	$(RM) -r priv/myhtmlex*
	$(RM) priv/fasthtml_worker
	$(RM) myhtmlex-*.tar
	$(RM) -r package-test

clean-myhtml:
	$(MAKE) -C $(MYHTML_PATH) clean
