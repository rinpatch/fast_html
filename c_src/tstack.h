#ifndef TSTACK_H
#define TSTACK_H

#define GROW_BY 30

typedef struct {
  lxb_dom_node_t **data;
  size_t used;
  size_t size;
} tstack;

void tstack_init(tstack *stack, size_t initial_size) {
  stack->data = (lxb_dom_node_t **) malloc(initial_size * sizeof(lxb_dom_node_t *));
  stack->used = 0;
  stack->size = initial_size;
}

void tstack_free(tstack *stack) {
  free(stack->data);
}

void tstack_resize(tstack *stack, size_t new_size) {
  stack->data = (lxb_dom_node_t **) realloc(stack->data, new_size * sizeof(lxb_dom_node_t *));
  stack->size = new_size;
}

void tstack_push(tstack *stack, lxb_dom_node_t * element) {
  if(stack->used == stack->size) {
    tstack_resize(stack, stack->size + GROW_BY);
  }
  stack->data[stack->used++] = element;
}

lxb_dom_node_t * tstack_pop(tstack *stack) {
 return stack->data[--(stack->used)];
}

#endif
