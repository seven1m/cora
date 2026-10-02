#ifndef CORA_RUBY_IO_H
#define CORA_RUBY_IO_H
#include "../ruby.h"
typedef struct { int fd; } rb_io_t;
int rb_io_descriptor(VALUE io);
rb_io_t *rb_io_get_io_pointer(VALUE io);
#define GetOpenFile(io, fptr) ((fptr) = rb_io_get_io_pointer(io))
void rb_io_set_nonblock(rb_io_t *fptr);
#endif
