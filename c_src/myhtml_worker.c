#include <stdlib.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <errno.h>
#include <ctype.h>

#include "erl_interface.h"
#include "ei.h"

#include "tstack.h"

#include <myhtml/myhtml.h>
#include <myhtml/mynamespace.h>

#define BUFFER_SIZE 1000

typedef struct _state_t {
  int fd;
  myhtml_t* myhtml;
} state_t;

void
handle_emsg(state_t* state, ErlMessage* emsg);
void
handle_send(state_t* state, ErlMessage* emsg);
ETERM*
decode(state_t* state, ErlMessage* emsg, ETERM* bin, ETERM* args);
ETERM*
build_tree(myhtml_tree_t* tree, myhtml_tree_node_t* node, unsigned char* parse_flags);
ETERM*
build_node_attrs(myhtml_tree_t* tree, myhtml_tree_node_t* node);
ETERM*
err_term(const char* error_atom);
unsigned char
read_parse_flags(ETERM* list);
static inline char *
lowercase(char* c);

const unsigned char FLAG_HTML_ATOMS       = 1 << 0;
const unsigned char FLAG_NIL_SELF_CLOSING = 1 << 1;
const unsigned char FLAG_COMMENT_TUPLE3   = 1 << 2;

int main(int argc, char **argv) {
  if (argc != 5 || !strcmp(argv[1],"-h") || !strcmp(argv[1],"--help")) {
    printf("\nUsage: ./priv/cnode_server <sname> <hostname> <cookie> <tname>\n\n");
    printf("    sname      the short name you want this c-node to connect as\n");
    printf("    hostname   the hostname\n");
    printf("    cookie     the authentication cookie\n");
    printf("    tname      the target node short name to connect to");
    return 0;
  }

  char *sname = argv[1];
  char *hostname = argv[2];
  char *cookie = argv[3];
  char *tname = argv[4];
  char full_name[1024];
  char target_node[1024];

  snprintf(full_name, sizeof full_name, "%s@%s", sname, hostname);
  snprintf(target_node, sizeof target_node, "%s@%s", tname, hostname);

  struct in_addr addr;
  addr.s_addr = htonl(INADDR_ANY);

  // fd to erlang node
  state_t* state = (state_t*)malloc(sizeof(state_t));
  bool looping = true;
  int buffer_size = BUFFER_SIZE;
  unsigned char* bufferpp = (unsigned char*)malloc(BUFFER_SIZE);
  ErlMessage emsg;

  // initialize all of Erl_Interface
  erl_init(NULL, 0);

  // initialize this node
  printf("initialising %s\n", full_name); fflush(stdout);
  if ( erl_connect_xinit(hostname, sname, full_name, &addr, cookie, 0) == -1 )
    erl_err_quit("error erl_connect_init");

  // connect to target node
  printf("connecting to %s\n", target_node); fflush(stdout);
  if ((state->fd = erl_connect(target_node)) < 0)
    erl_err_quit("erl_connect");

  state->myhtml = myhtml_create();
  myhtml_init(state->myhtml, MyHTML_OPTIONS_DEFAULT, 1, 0);

  // signal to stdout that we are ready
  printf("%s ready\n", full_name); fflush(stdout);

  while (looping)
  {
    // erl_xreceive_msg adapts the buffer width
    switch( erl_xreceive_msg(state->fd, &bufferpp, &buffer_size, &emsg) )
    // erl_receive_msg, uses a fixed buffer width
    /* switch( erl_receive_msg(state->fd, buffer, BUFFER_SIZE, &emsg) ) */
    {
      case ERL_TICK:
        // ignore
        break;
      case ERL_ERROR:
        // On failure, the function returns ERL_ERROR and sets erl_errno to one of:
        //
        // EMSGSIZE
        // Buffer is too small.
        // ENOMEM
        // No more memory is available.
        // EIO
        // I/O error.
        //
        // TODO: what is the correct reaction?
        looping = false;
        break;
      default:
        handle_emsg(state, &emsg);
    }
  }

  // shutdown: free all erlang terms still around
  erl_eterm_release();
  free(bufferpp);

  myhtml_destroy(state->myhtml);
  free(state);

  return EXIT_SUCCESS;
}

void
handle_emsg(state_t* state, ErlMessage* emsg)
{
  switch(emsg->type)
  {
    case ERL_REG_SEND:
    case ERL_SEND:
      handle_send(state, emsg);
      break;
    case ERL_LINK:
    case ERL_UNLINK:
      break;
    case ERL_EXIT:
      break;
  }
  // its our responsibility to free these pointers
  erl_free_compound(emsg->msg);
  erl_free_compound(emsg->to);
  erl_free_compound(emsg->from);
}

void
handle_send(state_t* state, ErlMessage* emsg)
{
  ETERM *decode_pattern = erl_format("{decode, Bin, Args}");
  ETERM *response;

  if (erl_match(decode_pattern, emsg->msg))
  {
    ETERM *bin = erl_var_content(decode_pattern, "Bin");
    ETERM *args = erl_var_content(decode_pattern, "Args");

    response = decode(state, emsg, bin, args);

    // free allocated resources
    erl_free_term(bin);
    erl_free_term(args);
  }
  else
  {
    response = err_term("unknown_call");
    return;
  }

  // send response
  erl_send(state->fd, emsg->from, response);

  // free allocated resources
  erl_free_compound(response);
  erl_free_term(decode_pattern);

  // free the free-list
  erl_eterm_release();

  return;
}

ETERM*
err_term(const char* error_atom)
{
  /* ETERM* tuple2[] = {erl_mk_atom("error"), erl_mk_atom(error_atom)}; */
  /* return erl_mk_tuple(tuple2, 2); */
  return erl_format("{error, ~w}", erl_mk_atom(error_atom));
}

ETERM*
decode(state_t* state, ErlMessage* emsg, ETERM* bin, ETERM* args)
{
  unsigned char parse_flags = 0;

  if (!ERL_IS_BINARY(bin) || !ERL_IS_LIST(args))
  {
    return err_term("badarg");
  }

  // get contents of binary argument
  char* binary = (char*)ERL_BIN_PTR(bin);
  size_t binary_len = ERL_BIN_SIZE(bin);

  myhtml_tree_t* tree = myhtml_tree_create();
  myhtml_tree_init(tree, state->myhtml);

  // parse tree
  mystatus_t status = myhtml_parse(tree, MyENCODING_UTF_8, binary, binary_len);
  if (status != MyHTML_STATUS_OK)
  {
    return err_term("myhtml_parse_failed");
  }

  // read parse flags
  parse_flags = read_parse_flags(args);

  // build tree
  myhtml_tree_node_t *root = myhtml_tree_get_document(tree);
  ETERM* result = build_tree(tree, myhtml_node_last_child(root), &parse_flags);
  myhtml_tree_destroy(tree);

  return result;
}

unsigned char
read_parse_flags(ETERM* list)
{
  unsigned char parse_flags = 0;
  ETERM *flag;
  ETERM *html_atoms = erl_mk_atom("html_atoms");
  ETERM *nil_self_closing = erl_mk_atom("nil_self_closing");
  ETERM *comment_tuple3 = erl_mk_atom("comment_tuple3");

  for (; !ERL_IS_EMPTY_LIST(list); list = ERL_CONS_TAIL(list)) {
    flag = ERL_CONS_HEAD(list);
    if (erl_match(html_atoms, flag))
    {
      parse_flags |= FLAG_HTML_ATOMS;
    }
    else if (erl_match(nil_self_closing, flag))
    {
      parse_flags |= FLAG_NIL_SELF_CLOSING;
    }
    else if (erl_match(comment_tuple3, flag))
    {
      parse_flags |= FLAG_COMMENT_TUPLE3;
    }
  }

  erl_free_term(html_atoms);
  erl_free_term(nil_self_closing);
  erl_free_term(comment_tuple3);

  return parse_flags;
}

ETERM* build_tree(myhtml_tree_t* tree, myhtml_tree_node_t* node, unsigned char* parse_flags)
{
  ETERM* result;
  ETERM* atom_nil = erl_mk_atom("nil");
  ETERM* empty_list = erl_mk_empty_list();
  myhtml_tree_node_t* prev_node = NULL;

  tstack stack;
  tstack_init(&stack, 30);
  for(myhtml_tree_node_t* current_node = node;;) {
    ETERM* children;

    // If we are going up the tree, get the children from the stack
    if (prev_node && !(current_node->next == prev_node || current_node->parent == prev_node)) {
      children = tstack_pop(&stack);
    // Else, try to go down the tree
    } else if(current_node->last_child) {
      tstack_push(&stack, erl_mk_empty_list());

      prev_node = current_node;
      current_node = current_node->last_child;

      continue;
    } else {
      if ((myhtml_node_is_close_self(current_node)  || myhtml_node_is_void_element(current_node))
      && (*parse_flags & FLAG_NIL_SELF_CLOSING)) {
        children = atom_nil;
      } else {
        children = empty_list;
      }
    }

    myhtml_tag_id_t tag_id = myhtml_node_tag_id(current_node);
    myhtml_namespace_t tag_ns = myhtml_node_namespace(current_node);

    if (tag_id == MyHTML_TAG__TEXT)
    {
      size_t text_len;

      const char* node_text = myhtml_node_text(current_node, &text_len);
      result = erl_mk_binary(node_text, text_len);
    }
    else if (tag_id == MyHTML_TAG__COMMENT)
    {
      size_t comment_len;
      const char* node_comment = myhtml_node_text(current_node, &comment_len);

      // For <!----> myhtml_node_text will return a null pointer, which will make erl_format segfault
      ETERM* comment = erl_mk_binary(node_comment ? node_comment : "", comment_len);

      if (*parse_flags & FLAG_COMMENT_TUPLE3)
      {
        result = erl_format("{comment, [], ~w}", comment);
      }
      else
      {
        result = erl_format("{comment, ~w}", comment);
      }
    }
    else
    {
      ETERM* tag;
      ETERM* attrs;

      // get name of tag
      size_t tag_name_len;
      const char *tag_name = myhtml_tag_name_by_id(tree, tag_id, &tag_name_len);
      // get namespace of tag
      size_t tag_ns_len;
      const char *tag_ns_name_ptr = myhtml_namespace_name_by_id(tag_ns, &tag_ns_len);
      char buffer [tag_ns_len + tag_name_len + 2];
      char *tag_string = buffer;
      size_t tag_string_len;

      if (tag_ns != MyHTML_NAMESPACE_HTML)
      {
        // tag_ns_name_ptr is unmodifyable, copy it in our tag_ns_buffer to make it modifyable.
	// +1 because myhtml uses strlen for length returned, which doesn't include the null-byte
	// https://github.com/lexborisov/myhtml/blob/0ade0e564a87f46fd21693a7d8c8d1fa09ffb6b6/source/myhtml/mynamespace.c#L80
        char tag_ns_buffer[tag_ns_len + 1];
        strncpy(tag_ns_buffer, tag_ns_name_ptr, sizeof(tag_ns_buffer));
        lowercase(tag_ns_buffer);

        tag_string_len = tag_ns_len + tag_name_len + 1; // +1 for colon
	snprintf(tag_string, sizeof(buffer), "%s:%s", tag_ns_buffer, tag_name);
      }
      else
      {
        strncpy(tag_string, tag_name, sizeof(buffer));
        tag_string_len = tag_name_len;
      }

      // attributes
      attrs = build_node_attrs(tree, current_node);

      if (!(*parse_flags & FLAG_HTML_ATOMS) || (tag_id == MyHTML_TAG__UNDEF || tag_id == MyHTML_TAG_LAST_ENTRY || tag_ns != MyHTML_NAMESPACE_HTML))
        tag = erl_mk_binary(tag_string, tag_string_len);
      else
        tag = erl_mk_atom(tag_string);

      result = erl_format("{~w, ~w, ~w}", tag, attrs, children);
    }

    if (stack.used == 0) {
      tstack_free(&stack);
      break;
    } else {
      tstack_push(&stack, erl_cons(result, tstack_pop(&stack)));
      prev_node = current_node;
      current_node = current_node->prev ? current_node->prev : current_node->parent;
    }
  }

  erl_free_term(atom_nil);

  return result;
}

ETERM*
build_node_attrs(myhtml_tree_t* tree, myhtml_tree_node_t* node)
{
  myhtml_tree_attr_t* attr;

  ETERM* list = erl_mk_empty_list();

  for (attr = myhtml_node_attribute_last(node); attr != NULL; attr = myhtml_attribute_prev(attr))
  {
    ETERM* name;
    ETERM* value;
    ETERM* attr_tuple;

    size_t attr_name_len;
    const char *attr_name = myhtml_attribute_key(attr, &attr_name_len);
    size_t attr_value_len;
    const char *attr_value = myhtml_attribute_value(attr, &attr_value_len);

    /* guard against poisoned attribute nodes */
    if (! attr_name_len)
      continue;

    name = erl_mk_binary(attr_name, attr_name_len);
    value = attr_value_len ? erl_mk_binary(attr_value, attr_value_len) : name;

    /* ETERM* tuple2[] = {name, value}; */
    /* attr_tuple = erl_mk_tuple(tuple2, 2); */
    attr_tuple = erl_format("{~w, ~w}", name, value);

    list = erl_cons(attr_tuple, list);
  }

  return list;
}

static inline char*
lowercase(char* c)
{
  char* p = c;
  while(*p)
  {
    *p = tolower((unsigned char)*p);
    p++;
  }
  return c;
}

