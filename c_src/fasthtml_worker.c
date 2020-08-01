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

#define HEADER_SIZE 4

#include <lexbor/html/html.h>
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
  ei_x_buff buffer;
} state_t;

typedef enum parse_flags_e {
  FLAG_HTML_ATOMS       = 1 << 0,
  FLAG_NIL_SELF_CLOSING = 1 << 1,
  FLAG_COMMENT_TUPLE3   = 1 << 2
} parse_flags_t;

char* read_packet(int *len);
static void handle_send(state_t * state);
static void err_term(ei_x_buff * response, const char * error_atom);
static parse_flags_t decode_parse_flags(state_t * state, int arity);
static void decode(state_t * state, ei_x_buff * response, lxb_html_document_t *document, bool fragment, lxb_dom_element_t *context_element, lxb_char_t * bin_data, size_t bin_size, parse_flags_t parse_flags);

static void build_tree(ei_x_buff * response, lxb_dom_node_t* tree, parse_flags_t parse_flags);
static void prepare_node_attrs(ei_x_buff * response, lxb_dom_node_t* node);

static inline char * lowercase(char * c);

static void panic(const char *fmt, ...) AFP(1, 2);
static void panic(const char *fmt, ...) {
  char buf[4096];
  va_list va;

  va_start (va, fmt);
  vsnprintf (buf, sizeof buf, fmt, va);
  va_end (va);

  fprintf (stderr, "fast_html worker: error: %s\n", buf);
  exit (EXIT_FAILURE);
}

int main(int argc, const char *argv[]) {
   state_t* state = calloc (1, sizeof(state_t));

#ifdef OTP_22_OR_NEWER
  // initialize erlang client library
  ei_init ();
#else
  erl_init (NULL, -1);
#endif

  ei_x_new (&state->buffer);

  fflush (stdout);

  while (true) {
    int len;
    char* buf = read_packet(&len);
    ei_x_free(&state->buffer);
    state->buffer.index = 0;
    state->buffer.buff = buf;
    state->buffer.buffsz = len;
    handle_send (state);
  }

  // shutdown: free all state
  ei_x_free (&state->buffer);
  free (state);

  return EXIT_SUCCESS;
}


/*
 * Reads a packet from Erlang.  The packet must be a standard {packet, 2}
 * packet.  This function aborts if any error is detected (including EOF).
 *
 * Returns: The number of bytes in the packet.
 */

char *read_packet(int *len)
{

    char* io_buf = NULL; /* Buffer for file i/o. */
    unsigned char header[HEADER_SIZE];
    uint32_t packet_length;	/* Length of current packet. */
    uint32_t bytes_read;
    uint32_t total_bytes_read;
    
    /*
     * Read the packet header.
     */
    
    total_bytes_read = read(STDIN_FILENO, header, HEADER_SIZE);

    if (total_bytes_read == 0) {
       exit(0);
    }
    if (total_bytes_read != HEADER_SIZE) {
	panic("Failed to read packet header, read: %d\n", total_bytes_read);
    }

    /*
     * Get the length of this packet.
     */
	
    packet_length = 0;

    for (int i = 0; i < HEADER_SIZE; i++)
	packet_length = (packet_length << 8) | header[i];

    *len=packet_length;
    
    if ((io_buf = (char *) malloc(packet_length)) == NULL) {
	panic("insufficient memory for i/o buffer of size %d\n", packet_length);
    }

    /*
     * Read the packet itself.
     */
    
    total_bytes_read = 0;

    while((bytes_read = read(STDIN_FILENO, (io_buf + total_bytes_read), (packet_length - total_bytes_read))))
      total_bytes_read += bytes_read;

    if (total_bytes_read != packet_length) {
	free(io_buf);
	panic("couldn't read packet of length %d, read: %d\r\n",
		packet_length, total_bytes_read);
    }

    return io_buf;
}

// handle ERL_SEND message type.
// we expect a tuple with arity of 3 or 4 in state->buffer.
// we expect the first argument to be an atom (`decode` or `decode_fragment`),
// the second argument to be the HTML payload, and the
// third argument to be the argument list.
// In case of `decode_fragment`, the fourth argument should be
// the context tag name.
// any other message: respond with an {error, unknown_call} tuple.
static void handle_send (state_t * state)
{
  // response holds our response, prepare it
  ei_x_buff response;

  ei_x_new (&response);

  // check the protocol version, if it's unsupported, panic
  int version;
  if (ei_decode_version (state->buffer.buff, &state->buffer.index, &version) < 0)
    panic ("malformed message - bad version (%d).", version);

  // decode the tuple header
  int arity;
  if (ei_decode_tuple_header (state->buffer.buff, &state->buffer.index, &arity) < 0)
  {
    err_term (&response, "badmatch");
    goto out;
  }

  char atom[MAXATOMLEN];
  if (ei_decode_atom (state->buffer.buff, &state->buffer.index, atom) < 0)
  {
    err_term (&response, "badmatch");
    goto out;
  }

  bool fragment = false;
  if (strcmp (atom, "decode"))
  {
    if (strcmp (atom, "decode_fragment")) {
      err_term (&response, "unknown_call");
      goto out;
    } else if (arity != 4) {
      err_term (&response, "badmatch");
      goto out;
    } else {
      fragment = true;
    }
  } else if (arity != 3) {
    err_term (&response, "badmatch");
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

  // Lists with items always have an empty list as their tail
  if (arity != 0)
    if (ei_decode_list_header (state->buffer.buff, &state->buffer.index, &arity) < 0)
      panic ("failed to decode empty list header after option list in message");

  lxb_html_document_t *document = lxb_html_document_create();
  lxb_dom_element_t *context_element = NULL;

  // if we are parsing a fragment, context tag name should come next
  if (fragment) {
    int context_bin_type, context_bin_size;
    if (ei_get_type (state->buffer.buff, &state->buffer.index, &context_bin_type, &context_bin_size) < 0)
      panic ("failed to decode binary size in message");

    // verify the type
    if (context_bin_type != ERL_BINARY_EXT)
    {
      err_term (&response, "badmatch");
      goto out;
    }

    // decode the binary
    char* context_bin_data = calloc (1, context_bin_size + 1);
    if (ei_decode_binary (state->buffer.buff, &state->buffer.index, context_bin_data, NULL) < 0)
      panic ("failed to decode context binary in message");

    context_element = lxb_dom_document_create_element(&document->dom_document, (lxb_char_t*) context_bin_data, context_bin_size, NULL);
    free (context_bin_data);
  }
  
  if (context_element && lxb_dom_element_tag_id(context_element) >= LXB_TAG__LAST_ENTRY) {
    err_term (&response, "unknown_context_tag");
  } else {
    decode (state, &response, document, fragment, context_element, (lxb_char_t *) bin_data, bin_size, parse_flags);
  }
  lxb_html_document_destroy(document);
  free (bin_data);

out: ;
  // send response
  unsigned char header[HEADER_SIZE];
  uint32_t size = (uint32_t) response.index;

  for (int i = HEADER_SIZE-1; i != -1; i--) {
    header[i] = (unsigned char) size & 0xFF;
    size = size >> 8;
  }

  write(STDOUT_FILENO, header, sizeof(header));
  write(STDOUT_FILENO, response.buff, response.index);
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

static void decode(state_t * state, ei_x_buff * response, lxb_html_document_t *document, bool fragment, lxb_dom_element_t *context_element, lxb_char_t * bin_data, size_t bin_size, parse_flags_t parse_flags)
{
  // parse tree
  lxb_status_t status;
  lxb_dom_node_t *node;

  if (fragment) {
    node = lxb_html_document_parse_fragment(document, context_element, bin_data, bin_size);
    status = (node == NULL)? LXB_STATUS_ERROR : LXB_STATUS_OK;
  } else {
    status = lxb_html_document_parse(document, bin_data, bin_size);
    node = lxb_dom_interface_node(document);
  }

  if (status != LXB_STATUS_OK)
  {
    err_term (response, "parse_failed");
    return;
  }

  // build tree
  build_tree (response, node, parse_flags);
}

// a tag is sent as a tuple:
// - a string or atom for the tag name
// - an attribute list
// - a children list
// in this function, we prepare the atom and complete attribute list
static void prepare_tag_header (ei_x_buff * response, const char * tag_string, lxb_dom_node_t* node, parse_flags_t parse_flags)
{
  lxb_tag_id_t tag_id = lxb_dom_node_tag_id(node);

  ei_x_encode_tuple_header (response, 3);

  if (! (parse_flags & FLAG_HTML_ATOMS) || (tag_id == LXB_TAG__UNDEF || tag_id >= LXB_TAG__LAST_ENTRY))
    ei_x_encode_binary (response, tag_string, strlen (tag_string));
  else
    ei_x_encode_atom (response, tag_string);

  prepare_node_attrs (response, node);
}

// prepare an attribute node
static void prepare_node_attrs(ei_x_buff * response, lxb_dom_node_t* node)
{
  lxb_dom_attr_t *attr;

  for (attr = lxb_dom_element_first_attribute(lxb_dom_interface_element(node)); attr != NULL; attr = lxb_dom_element_next_attribute(attr))
  {
    size_t attr_name_len;
    char *attr_name = (char*) lxb_dom_attr_qualified_name(attr, &attr_name_len);
    size_t attr_value_len;
    const char *attr_value = (char*) lxb_dom_attr_value(attr, &attr_value_len);

    /* guard against poisoned attribute nodes */
    if (! attr_name_len)
      continue;

    ei_x_encode_list_header (response, 1);
    ei_x_encode_tuple_header (response, 2);
    ei_x_encode_binary (response, attr_name, attr_name_len);

    ei_x_encode_binary (response, attr_value, attr_value_len);
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

static void build_tree (ei_x_buff * response, lxb_dom_node_t* node, parse_flags_t parse_flags)
{
  tstack stack;
  tstack_init (&stack, 30);
  tstack_push (&stack, node);

  lxb_dom_node_t* current_node = node->first_child;

  // ok we're going to send an actual response so start encoding it
  response->index = 0;
  ei_x_encode_version (response);
  ei_x_encode_tuple_header(response, 2);
  ei_x_encode_atom(response, "ok");

  if (current_node == NULL) {
    EMIT_EMPTY_LIST_HDR;
    EMIT_LIST_TAIL;
  }
  while (current_node != NULL)
  {
    if (current_node->type == LXB_DOM_NODE_TYPE_TEXT)
    {
      size_t text_len;
      const char * node_text = (char*) lxb_dom_node_text_content(current_node, &text_len);
      EMIT_LIST_HDR;
      ei_x_encode_binary (response, node_text, text_len);
    }
    else if (current_node->type == LXB_DOM_NODE_TYPE_COMMENT)
    {
      size_t comment_len;
      const char* node_comment = (char*) lxb_dom_node_text_content(current_node, &comment_len);

      EMIT_LIST_HDR;
      prepare_comment(response, node_comment, comment_len, parse_flags);
    }
    else if(current_node->type == LXB_DOM_NODE_TYPE_ELEMENT)
    {
      // get name of tag
      size_t tag_name_len;
      const char *tag_name = (char*) lxb_dom_element_qualified_name(lxb_dom_interface_element(current_node), &tag_name_len);
      EMIT_LIST_HDR;
      prepare_tag_header (response, tag_name, current_node, parse_flags);

      if (current_node->first_child)
      {
        tstack_push (&stack, current_node);
        current_node = current_node->first_child;

        continue;
      }
      else
      {
        if (parse_flags & FLAG_NIL_SELF_CLOSING && lxb_html_tag_is_void(lxb_dom_node_tag_id(current_node))) {
  
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
