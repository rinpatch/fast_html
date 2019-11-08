#include <stdlib.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <errno.h>
#include <ctype.h>

#ifndef _REENTRANT
#define _REENTRANT /* For some reason __erl_errno is undefined unless _REENTRANT is defined */
#endif

#include "ei.h"
#ifndef OTP_22_OR_NEWER
# include "erl_interface.h"
#endif

#include <myhtml/myhtml.h>
#include <myhtml/mynamespace.h>

#include "tstack.h"

#ifdef __GNUC__
# define AFP(x, y) __attribute__((format (printf, x, y)))
#else
# define AFP(x, y)
#endif

#ifdef __GNUC__
# define NORETURN __attribute__((noreturn))
#else
# define NORETURN
#endif

typedef struct _state_t {
  int fd;
  myhtml_t * myhtml;
  ei_cnode ec;
  bool looping;
  ei_x_buff buffer;
} state_t;

typedef enum parse_flags_e {
  FLAG_HTML_ATOMS       = 1 << 0,
  FLAG_NIL_SELF_CLOSING = 1 << 1,
  FLAG_COMMENT_TUPLE3   = 1 << 2
} parse_flags_t;

static void handle_emsg(state_t * state, erlang_msg * emsg);
static void handle_send(state_t * state, erlang_msg * emsg);
static void err_term(ei_x_buff * response, const char * error_atom);
static parse_flags_t decode_parse_flags(state_t * state, int arity);
static void decode(state_t * state, ei_x_buff * response, const char * bin_data, size_t bin_size, parse_flags_t parse_flags);

static void build_tree(ei_x_buff * response, myhtml_tree_t * tree, myhtml_tree_node_t * node, parse_flags_t parse_flags);
static void prepare_node_attrs(ei_x_buff * response, myhtml_tree_node_t * node);

static inline char * lowercase(char * c);

static void panic(const char *fmt, ...) AFP(1, 2);
static void panic(const char *fmt, ...) {
  char buf[4096];
  va_list va;

  va_start (va, fmt);
  vsnprintf (buf, sizeof buf, fmt, va);
  va_end (va);

  fprintf (stderr, "myhtml worker: error: %s\n", buf);
  exit (EXIT_FAILURE);
}

static void usage (void) NORETURN;
static void usage (void) {
  fputs ("usage: myhtml_worker sname hostname cookie tname\n\n"
         "   sname      the short name you want this c-node to connect as\n"
         "   hostname   the hostname\n"
         "   cookie     the authentication cookie\n"
         "   tname      the target node short name to connect to\n", stderr);
  exit (EXIT_FAILURE);
}

int main(int argc, const char *argv[]) {
#ifdef OTP_22_OR_NEWER
  // initialize erlang client library
  ei_init ();
#else
  erl_init (NULL, -1);
#endif

  if (argc != 5)
    usage ();

  const char *sname = argv[1];
  const char *hostname = argv[2];
  const char *cookie = argv[3];
  const char *tname = argv[4];

  char full_name[1024];
  char target_node[1024];

  snprintf (full_name, sizeof full_name, "%s@%s", sname, hostname);
  snprintf (target_node, sizeof target_node, "%s@%s", tname, hostname);

  struct in_addr addr;
  addr.s_addr = htonl(INADDR_ANY);

  // fd to erlang node
  state_t* state = calloc (1, sizeof(state_t));
  state->looping = true;
  ei_x_new (&state->buffer);

  // initialize this node
  printf ("initialising %s\n", full_name);
  if (ei_connect_xinit (&state->ec, hostname, sname, full_name, &addr, cookie, 0) == -1)
    panic ("ei_connect_xinit failed.");

  // connect to target node
  printf ("connecting to %s\n", target_node);
  if ((state->fd = ei_connect (&state->ec, target_node)) < 0)
    panic ("ei_connect failed.");

  state->myhtml = myhtml_create ();
  myhtml_init (state->myhtml, MyHTML_OPTIONS_DEFAULT, 1, 0);

  // signal to stdout that we are ready
  printf ("%s ready\n", full_name);
  fflush (stdout);

  while (state->looping)
  {
    erlang_msg emsg;

    switch (ei_xreceive_msg (state->fd, &emsg, &state->buffer))
    {
      case ERL_TICK:
        break;
      case ERL_ERROR:
        panic ("ei_xreceive_msg: %s\n", strerror (erl_errno));
        break;
      default:
        handle_emsg (state, &emsg);
        break;
    }
  }

  // shutdown: free all state
  ei_x_free (&state->buffer);
  myhtml_destroy (state->myhtml);
  free (state);

  return EXIT_SUCCESS;
}

// handle an erlang_msg structure and call handle_send() if relevant
static void handle_emsg (state_t * state, erlang_msg * emsg)
{
  state->buffer.index = 0;

  switch (emsg->msgtype)
  {
    case ERL_REG_SEND:
    case ERL_SEND:
      handle_send (state, emsg);
      break;
    case ERL_LINK:
    case ERL_UNLINK:
      break;
    case ERL_EXIT:
      break;
  }
}

// handle ERL_SEND message type.
// we expect a tuple with arity of 3 in state->buffer.
// we expect the first argument to be an atom (`decode`),
// the second argument to be the HTML payload, and the
// third argument to be the argument list.
// any other message: respond with an {error, unknown_call} tuple.
static void handle_send (state_t * state, erlang_msg * emsg)
{
  // response holds our response, prepare it
  ei_x_buff response;

  ei_x_new (&response);

  // check the protocol version, if it's unsupported, panic
  int version;
  if (ei_decode_version (state->buffer.buff, &state->buffer.index, &version) < 0)
    panic ("malformed message - bad version (%d).", version);

  // decode the tuple header, make sure we have an arity of 3.
  int arity;
  if (ei_decode_tuple_header (state->buffer.buff, &state->buffer.index, &arity) < 0 || arity != 3)
  {
    err_term (&response, "badmatch");
    goto out;
  }

  // the tuple should begin with a `decode` atom.
  char atom[MAXATOMLEN];
  if (ei_decode_atom (state->buffer.buff, &state->buffer.index, atom) < 0)
  {
    err_term (&response, "badmatch");
    goto out;
  }

  if (strcmp (atom, "decode"))
  {
    err_term (&response, "unknown_call");
    goto out;
  }

  // the next argument should be a binary, allocate it dynamically.
  int bin_type, bin_size;
  if (ei_get_type (state->buffer.buff, &state->buffer.index, &bin_type, &bin_size) < 0)
    panic ("failed to decode binary size in message");

  // verify the type
  if (bin_type != ERL_BINARY_EXT)
  {
    err_term (&response, "badmatch");
    goto out;
  }

  // decode the binary
  char * bin_data = calloc (1, bin_size + 1);
  if (ei_decode_binary (state->buffer.buff, &state->buffer.index, bin_data, NULL) < 0)
    panic ("failed to decode binary in message");

  // next should be the options list
  if (ei_decode_list_header (state->buffer.buff, &state->buffer.index, &arity) < 0)
    panic ("failed to decode options list header in message");

  parse_flags_t parse_flags = decode_parse_flags (state, arity);
  decode (state, &response, bin_data, bin_size, parse_flags);

  free (bin_data);

out:
  // send response
  ei_send (state->fd, &emsg->from, response.buff, response.buffsz);

  // free response
  ei_x_free (&response);

  return;
}

static void err_term (ei_x_buff * response, const char * error_atom)
{
  response->index = 0;
  ei_x_encode_version (response);
  ei_x_encode_tuple_header (response, 2);
  ei_x_encode_atom (response, "error");
  ei_x_encode_atom (response, error_atom);
}

static parse_flags_t decode_parse_flags (state_t * state, int arity)
{
  parse_flags_t parse_flags = 0;

  for (int i = 0; i < arity; i++)
  {
    char atom[MAXATOMLEN];

    if (ei_decode_atom (state->buffer.buff, &state->buffer.index, atom) < 0)
      continue;

    if (! strcmp ("html_atoms", atom))
      parse_flags |= FLAG_HTML_ATOMS;
    else if (! strcmp ("nil_self_closing", atom))
      parse_flags |= FLAG_NIL_SELF_CLOSING;
    else if (! strcmp ("comment_tuple3", atom))
      parse_flags |= FLAG_COMMENT_TUPLE3;
  }

  return parse_flags;
}

static void decode (state_t * state, ei_x_buff * response, const char * bin_data, size_t bin_size, parse_flags_t parse_flags)
{
  myhtml_tree_t * tree = myhtml_tree_create ();
  myhtml_tree_init (tree, state->myhtml);
  myhtml_tree_parse_flags_set (tree, MyHTML_TREE_PARSE_FLAGS_WITHOUT_DOCTYPE_IN_TREE);

  // parse tree
  mystatus_t status = myhtml_parse (tree, MyENCODING_UTF_8, bin_data, bin_size);
  if (status != MyHTML_STATUS_OK)
  {
    err_term (response, "myhtml_parse_failed");
    return;
  }

  // build tree
  myhtml_tree_node_t * root = myhtml_tree_get_document (tree);
  build_tree (response, tree, root->child, parse_flags);
  myhtml_tree_destroy (tree);
}

// a tag is sent as a tuple:
// - a string or atom for the tag name
// - an attribute list
// - a children list
// in this function, we prepare the atom and complete attribute list
static void prepare_tag_header (ei_x_buff * response, const char * tag_string, myhtml_tree_node_t * node, parse_flags_t parse_flags)
{
  myhtml_tag_id_t tag_id = myhtml_node_tag_id (node);
  myhtml_namespace_t tag_ns = myhtml_node_namespace (node);

  ei_x_encode_tuple_header (response, 3);

  if (! (parse_flags & FLAG_HTML_ATOMS) || (tag_id == MyHTML_TAG__UNDEF || tag_id == MyHTML_TAG_LAST_ENTRY || tag_ns != MyHTML_NAMESPACE_HTML))
    ei_x_encode_binary (response, tag_string, strlen (tag_string));
  else
    ei_x_encode_atom (response, tag_string);

  prepare_node_attrs (response, node);
}

// prepare an attribute node
static void prepare_node_attrs(ei_x_buff * response, myhtml_tree_node_t * node)
{
  myhtml_tree_attr_t * attr;

  for (attr = myhtml_node_attribute_first (node); attr != NULL; attr = myhtml_attribute_next (attr))
  {
    size_t attr_name_len;
    const char *attr_name = myhtml_attribute_key (attr, &attr_name_len);
    size_t attr_value_len;
    const char *attr_value = myhtml_attribute_value (attr, &attr_value_len);

    /* guard against poisoned attribute nodes */
    if (! attr_name_len)
      continue;

    ei_x_encode_list_header (response, 1);
    ei_x_encode_tuple_header (response, 2);
    ei_x_encode_binary (response, attr_name, attr_name_len);

    if (attr_value_len)
      ei_x_encode_binary (response, attr_value, attr_value_len);
    else
      ei_x_encode_binary (response, attr_name, attr_name_len);
  }

  ei_x_encode_empty_list (response);
}

// dump a comment node
static void prepare_comment (ei_x_buff * response, const char * node_comment, size_t comment_len, parse_flags_t parse_flags)
{
  ei_x_encode_tuple_header (response, parse_flags & FLAG_COMMENT_TUPLE3 ? 3 : 2);
  ei_x_encode_atom (response, "comment");

  if (parse_flags & FLAG_COMMENT_TUPLE3)
    ei_x_encode_list_header (response, 0);

  ei_x_encode_binary (response, node_comment, comment_len);
}

#ifdef DEBUG_LIST_MANIP

#define EMIT_LIST_HDR \
	printf ("list hdr for node %p\n", current_node); \
	fflush (stdout); \
	ei_x_encode_list_header (response, 1)

#define EMIT_EMPTY_LIST_HDR \
	printf ("list empty for node %p\n", current_node); \
	fflush (stdout); \
	ei_x_encode_list_header (response, 0)

#define EMIT_LIST_TAIL \
	printf ("list tail for node %p\n", current_node); \
	fflush (stdout); \
	ei_x_encode_empty_list (response)

#else

#define EMIT_LIST_HDR ei_x_encode_list_header (response, 1)
#define EMIT_EMPTY_LIST_HDR ei_x_encode_list_header (response, 0)
#define EMIT_LIST_TAIL ei_x_encode_empty_list (response)

#endif

static void build_tree (ei_x_buff * response, myhtml_tree_t * tree, myhtml_tree_node_t * node, parse_flags_t parse_flags)
{
  myhtml_tree_node_t * current_node = node;

  tstack stack;
  tstack_init (&stack, 30);

  // ok we're going to send an actual response so start encoding it
  response->index = 0;
  ei_x_encode_version (response);
  ei_x_encode_tuple_header(response, 2);
  ei_x_encode_atom(response, "myhtml_worker");

  while (current_node != NULL)
  {
    myhtml_tag_id_t tag_id = myhtml_node_tag_id (current_node);
    myhtml_namespace_t tag_ns = myhtml_node_namespace (current_node);

    if (tag_id == MyHTML_TAG__TEXT)
    {
      size_t text_len;
      const char * node_text = myhtml_node_text (current_node, &text_len);

      EMIT_LIST_HDR;
      ei_x_encode_binary (response, node_text, text_len);
    }
    else if (tag_id == MyHTML_TAG__COMMENT)
    {
      size_t comment_len;
      const char* node_comment = myhtml_node_text (current_node, &comment_len);

      EMIT_LIST_HDR;
      prepare_comment (response, node_comment, comment_len, parse_flags);
    }
    else
    {
      // get name of tag
      size_t tag_name_len;
      const char *tag_name = myhtml_tag_name_by_id (tree, tag_id, &tag_name_len);
      // get namespace of tag
      size_t tag_ns_len;
      const char *tag_ns_name_ptr = myhtml_namespace_name_by_id (tag_ns, &tag_ns_len);
      char buffer [tag_ns_len + tag_name_len + 2];
      char *tag_string = buffer;

      if (tag_ns != MyHTML_NAMESPACE_HTML)
      {
        // tag_ns_name_ptr is unmodifyable, copy it in our tag_ns_buffer to make it modifyable.
	// +1 because myhtml uses strlen for length returned, which doesn't include the null-byte
	// https://github.com/lexborisov/myhtml/blob/0ade0e564a87f46fd21693a7d8c8d1fa09ffb6b6/source/myhtml/mynamespace.c#L80
        char tag_ns_buffer[tag_ns_len + 1];
        strncpy (tag_ns_buffer, tag_ns_name_ptr, sizeof tag_ns_buffer);
        lowercase (tag_ns_buffer);

	snprintf (tag_string, sizeof buffer, "%s:%s", tag_ns_buffer, tag_name);
      }
      else
      {
        // strncpy length does not contain null, so blank the buffer before copying
        // and limit the copy length to buffer size minus one for safety.
        memset (tag_string, '\0', sizeof buffer);
        strncpy (tag_string, tag_name, sizeof buffer - 1);
      }

      if (stack.used > 0)
      {
        EMIT_LIST_HDR;
      }

      prepare_tag_header (response, tag_string, current_node, parse_flags);

      if (current_node->child)
      {
        tstack_push (&stack, current_node);
        current_node = current_node->child;

        continue;
      }
      else
      {
        if (parse_flags & FLAG_NIL_SELF_CLOSING && (myhtml_node_is_close_self(current_node) || myhtml_node_is_void_element(current_node)))
        {
#ifdef DEBUG_LIST_MANIP
          printf ("self-closing tag %s emit nil?\n", tag_string); fflush (stdout);
#endif
          ei_x_encode_atom (response, "nil");
        }
        else
        {
          EMIT_EMPTY_LIST_HDR;
        }
      }
    }

    if (current_node->next)
      current_node = current_node->next;
    else
    {
      while (! current_node->next && stack.used != 0)
      {
        EMIT_LIST_TAIL;
        current_node = tstack_pop (&stack);
      }

      if (current_node->next)
        current_node = current_node->next;
    }

    // are we at root?
    if (current_node == node)
      break;
  }

  tstack_free (&stack);
}

static inline char * lowercase(char* c)
{
  char * p = c;

  while (*p)
  {
    *p = tolower ((unsigned char) *p);
    p++;
  }

  return c;
}
