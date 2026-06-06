#ifndef CORA_RUBY_H
#define CORA_RUBY_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef uint64_t VALUE;
typedef struct { int _; } rb_encoding;

#define Qfalse ((VALUE)0x00)
#define Qtrue  ((VALUE)0x02)
#define Qnil   ((VALUE)0x04)
#define Qundef ((VALUE)0x06)

extern VALUE rb_cString;

char *rb_string_ptr(VALUE str);
long  rb_string_len(VALUE str);

void rb_define_method(VALUE klass, const char *name, void *func, int argc);

int           rb_encoding_get(VALUE str);
rb_encoding  *rb_enc_from_index(int idx);
unsigned int  rb_enc_codepoint_len(const char *p, const char *e, int *len_p, rb_encoding *enc);
int           rb_isspace(unsigned int c);

#define RSTRING_PTR(str)  rb_string_ptr(str)
#define RSTRING_LEN(str)  rb_string_len(str)
#define RSTRING_END(str)  (RSTRING_PTR(str) + RSTRING_LEN(str))
#define ENCODING_GET(str) rb_encoding_get(str)

#define RUBY_API_VERSION_CODE 30200

#ifdef __cplusplus
}
#endif

#endif
