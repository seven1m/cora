#ifndef CORA_RUBY_VM_H
#define CORA_RUBY_VM_H

#include "ruby.h"

typedef struct ruby_vm_struct ruby_vm_t;

void ruby_vm_at_exit(void (*func)(ruby_vm_t *));

#endif
