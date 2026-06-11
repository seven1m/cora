#ifndef CORA_RUBY_UTIL_H
#define CORA_RUBY_UTIL_H

#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <ctype.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ALLOC(type)       ((type *)xmalloc(sizeof(type)))
#define ALLOC_N(type, n)  ((type *)xcalloc((n), sizeof(type)))
#define REALLOC_N(type, ptr, n) ((type *)xrealloc((ptr), sizeof(type) * (n)))

void *rb_alloc_tmp_buffer(volatile VALUE *store, size_t size);
void  rb_free_tmp_buffer(volatile VALUE *store);
#define ALLOCV_N(type, v, n) ((type*)rb_alloc_tmp_buffer(&(v), (size_t)(n) * sizeof(type)))
#define ALLOCV_END(v) rb_free_tmp_buffer(&(v))

void *ruby_xmalloc(size_t size);
void *ruby_xcalloc(size_t n, size_t size);
void *ruby_xrealloc(void *ptr, size_t size);
void  ruby_xfree(void *ptr);

unsigned long ruby_scan_digits(const char *str, ssize_t len, int base, size_t *retlen, int *overflow);

#ifdef __cplusplus
}
#endif

#endif
