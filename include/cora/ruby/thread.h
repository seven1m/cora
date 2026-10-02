#ifndef CORA_RUBY_THREAD_H
#define CORA_RUBY_THREAD_H
#include "../ruby.h"
typedef void rb_unblock_function_t(void *);
#define RUBY_UBF_IO ((rb_unblock_function_t *)-1)
void *rb_thread_call_without_gvl(void *(*func)(void *), void *data, rb_unblock_function_t *unblock, void *unblock_data);
#endif
