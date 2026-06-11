#ifndef CORA_RUBY_H
#define CORA_RUBY_H

#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef uint64_t VALUE;
typedef unsigned long ID;
typedef struct { int _; } rb_encoding;

#define Qfalse ((VALUE)0x00)
#define Qtrue  ((VALUE)0x02)
#define Qnil   ((VALUE)0x04)
#define Qundef ((VALUE)0x06)

#define RUBY_IMMEDIATE_MASK 0x03
#define RUBY_FIXNUM_FLAG    0x01
#define RUBY_FLONUM_MASK    0x02

#define IMMEDIATE_P(x)   ((x) & RUBY_IMMEDIATE_MASK)
#define FIXNUM_P(x)      (IMMEDIATE_P(x) == RUBY_FIXNUM_FLAG)
#define NIL_P(x)         ((x) == Qnil)
#define RTEST(x)         ((x) & ~Qnil)

#define INT2FIX(x) (((VALUE)(x)) << 1 | RUBY_FIXNUM_FLAG)
#define FIX2LONG(x) ((long)((x) >> 1))

#define T_NONE     0x00
#define T_OBJECT   0x01
#define T_CLASS    0x02
#define T_MODULE   0x03
#define T_FLOAT    0x04
#define T_STRING   0x05
#define T_REGEXP   0x06
#define T_ARRAY    0x07
#define T_HASH     0x08
#define T_STRUCT   0x09
#define T_BIGNUM   0x0a
#define T_FILE     0x0b
#define T_DATA     0x0c
#define T_MATCH    0x0d
#define T_COMPLEX  0x0e
#define T_RATIONAL 0x0f
#define T_NIL      0x11
#define T_TRUE     0x12
#define T_FALSE    0x13
#define T_SYMBOL   0x14
#define T_FIXNUM   0x15
#define T_UNDEF    0x16
#define T_IMEMO    0x1a
#define T_MASK     0x1f

extern VALUE rb_cObject;
extern VALUE rb_cString;
extern VALUE rb_cArray;
extern VALUE rb_cHash;
extern VALUE rb_cInteger;
extern VALUE rb_cFloat;
extern VALUE rb_cSymbol;
extern VALUE rb_cRange;
extern VALUE rb_cRegexp;
extern VALUE rb_cClass;
extern VALUE rb_cModule;
extern VALUE rb_cProc;
extern VALUE rb_cNilClass;
extern VALUE rb_cTrueClass;
extern VALUE rb_cFalseClass;
extern VALUE rb_cNumeric;
extern VALUE rb_cStruct;
extern VALUE rb_cDir;
extern VALUE rb_cFile;
extern VALUE rb_cIO;
extern VALUE rb_cTime;
extern VALUE rb_cThread;
extern VALUE rb_cFiber;
extern VALUE rb_cEncoding;
extern VALUE rb_cEnumerator;
extern VALUE rb_cException;
extern VALUE rb_cStandardError;
extern VALUE rb_cRuntimeError;
extern VALUE rb_cArgumentError;
extern VALUE rb_cTypeError;
extern VALUE rb_cNameError;
extern VALUE rb_cNoMethodError;

extern VALUE rb_mKernel;
extern VALUE rb_mProcess;
extern VALUE rb_mSignal;
extern VALUE rb_mWarning;
extern VALUE rb_mMarshal;
extern VALUE rb_mErrno;

extern VALUE rb_eException;
extern VALUE rb_eStandardError;
extern VALUE rb_eRuntimeError;
extern VALUE rb_eArgError;
extern VALUE rb_eTypeError;
extern VALUE rb_eNameError;
extern VALUE rb_eNoMethodError;
extern VALUE rb_eNoMemError;
extern VALUE rb_eScriptError;
extern VALUE rb_eSyntaxError;
extern VALUE rb_eLoadError;
extern VALUE rb_eNotImpError;
extern VALUE rb_eSystemCallError;
extern VALUE rb_eFatal;
extern VALUE rb_eSignal;
extern VALUE rb_eInterrupt;
extern VALUE rb_eSystemExit;
extern VALUE rb_eLocalJumpError;
extern VALUE rb_eSysStackError;
extern VALUE rb_eRangeError;
extern VALUE rb_eFloatDomainError;
extern VALUE rb_eZeroDivError;
extern VALUE rb_eFrozenError;
extern VALUE rb_eThreadError;
extern VALUE rb_eKeyError;
extern VALUE rb_eIndexError;
extern VALUE rb_eStopIteration;
extern VALUE rb_eEOFError;
extern VALUE rb_eEncodingError;

extern VALUE rb_eEncCompatError;
extern VALUE rb_eNoMemoryError; /* same as rb_eNoMemError */
#define rb_eNoMemError rb_eNoMemoryError

#define RSTRING_PTR(str)  rb_string_ptr(str)
#define RSTRING_LEN(str)  rb_string_len(str)
#define RSTRING_END(str)  (RSTRING_PTR(str) + RSTRING_LEN(str))
#define ENCODING_GET(str) rb_encoding_get(str)

/* array macros */
VALUE rb_ary_entry(VALUE ary, long offset);
long  RARRAY_LEN(VALUE ary);
const VALUE *rb_ary_const_ptr(VALUE ary);
#define RARRAY_CONST_PTR(a) rb_ary_const_ptr(a)
#define RARRAY_PTR(a)       ((VALUE *)RARRAY_CONST_PTR(a))
#define RARRAY_AREF(a, i)   RARRAY_CONST_PTR(a)[i]

/* string macros */
#define StringValue(v)       rb_string_value(&(v))
#define StringValuePtr(v)    (rb_string_value_ptr(&(v)) ? rb_string_value_ptr(&(v)) : "")
#define StringValueCStr(v)   (rb_string_value_cstr(&(v)) ? rb_string_value_cstr(&(v)) : "")
#define SafeStringValue(v)   StringValue(v)

#define RB_GC_GUARD(v) ((void)(v))

/* integer conversion */
VALUE INT2NUM(long v);
long  NUM2INT(VALUE v);
long  NUM2LONG(VALUE v);
VALUE SIZET2NUM(size_t v);
VALUE LONG2NUM(long v);
VALUE UINT2NUM(unsigned int v);
VALUE ULONG2NUM(unsigned long v);

/* struct wrapping */
typedef struct rb_data_type_struct {
    const char *wrap_struct_name;
    struct {
        void (*dmark)(void*);
        void (*dfree)(void*);
        size_t (*dsize)(const void*);
        void *reserved[2];
    } function;
    const void *parent;
    void *data;
} rb_data_type_t;

#define RUBY_TYPED_DEFAULT_FREE NULL
#define RUBY_TYPED_NEVER_FREE   ((void (*)(void *))(-1))
#define RUBY_TYPED_FREE_IMMEDIATELY  NULL
#define RUBY_TYPED_WB_PROTECTED  1

VALUE TypedData_Wrap_Struct(VALUE klass, const rb_data_type_t *type, void *data);
VALUE rb_data_typed_object_alloc(VALUE klass, const rb_data_type_t *type);
void *Check_TypedStruct(VALUE obj, const rb_data_type_t *type);
#define TypedData_Make_Struct(klass, type_name, type, data) \
    ((data) = (type_name *)calloc(1, sizeof(type_name)), \
     TypedData_Wrap_Struct(klass, type, data))
#define TypedData_Get_Struct(obj, type_name, type, data) \
    ((data) = (type_name *)Check_TypedStruct(obj, type))

/* Check_Type */
void Check_Type(VALUE obj, int type);

/* functions */
char  *rb_string_ptr(VALUE str);
long   rb_string_len(VALUE str);
char  *rb_string_value_cstr(VALUE *ptr);
char  *rb_string_value_ptr(VALUE *ptr);
VALUE  rb_string_value(VALUE *ptr);

VALUE  rb_str_new(const char *ptr, long len);
VALUE  rb_str_new_cstr(const char *ptr);
VALUE  rb_str_new2(const char *ptr);
#define rb_str_new_cstr rb_str_new2
VALUE  rb_usascii_str_new_cstr(const char *ptr);
#define rb_usascii_str_new2 rb_usascii_str_new_cstr
VALUE  rb_enc_str_new(const char *ptr, long len, rb_encoding *enc);
VALUE  rb_utf8_str_new_cstr(const char *ptr);
VALUE  rb_str_export_to_enc(VALUE str, rb_encoding *enc);

VALUE  rb_ary_new(void);
VALUE  rb_ary_new3(long n, ...);
VALUE  rb_ary_new4(long n, const VALUE *elts);
VALUE  rb_ary_push(VALUE ary, VALUE item);

ID     rb_intern(const char *name);
VALUE  rb_const_get(VALUE klass, ID id);
VALUE  rb_const_get_at(VALUE klass, ID id);
void   rb_define_const(VALUE klass, const char *name, VALUE val);

VALUE  rb_funcall(VALUE recv, ID mid, int argc, ...);
VALUE  rb_funcallv(VALUE recv, ID mid, int argc, const VALUE *argv);
VALUE  rb_funcallv_public(VALUE recv, ID mid, int argc, const VALUE *argv);
#define rb_funcall3 rb_funcallv
VALUE  rb_yield(VALUE val);
VALUE  rb_yield_values(int n, ...);

VALUE  rb_attr_get(VALUE obj, ID id);
VALUE  rb_ivar_get(VALUE obj, ID id);
VALUE  rb_ivar_set(VALUE obj, ID id, VALUE val);
#define rb_iv_set(obj, name, val) rb_ivar_set(obj, rb_intern(name), val)

VALUE  rb_class_new_instance(int argc, const VALUE *argv, VALUE klass);
VALUE  rb_obj_alloc(VALUE klass);
VALUE  rb_class_of(VALUE obj);
VALUE  rb_obj_class(VALUE obj);

void   rb_raise(VALUE exc, const char *fmt, ...);
void   rb_exc_raise(VALUE exc);
void   rb_exc_set_message(VALUE exc, VALUE msg);
VALUE  rb_protect(VALUE (*proc)(VALUE), VALUE data, int *state);
VALUE  rb_ensure(VALUE (*b_proc)(VALUE), VALUE data1, VALUE (*e_proc)(VALUE), VALUE data2);
void   rb_jump_tag(int state);

int    rb_respond_to(VALUE obj, ID id);
int    rb_scan_args(int argc, const VALUE *argv, const char *fmt, ...);

void   rb_define_alloc_func(VALUE klass, VALUE (*func)(VALUE));
void   rb_define_singleton_method(VALUE obj, const char *name, void *func, int argc);
void   rb_define_module_function(VALUE module, const char *name, void *func, int argc);
void   rb_define_private_method(VALUE klass, const char *name, void *func, int argc);

VALUE  rb_define_module(const char *name);
VALUE  rb_define_module_under(VALUE outer, const char *name);
VALUE  rb_define_class_under(VALUE outer, const char *name, VALUE super);

void   rb_define_method(VALUE klass, const char *name, void *func, int argc);

void   rb_require(const char *name);
VALUE  rb_path_to_class(VALUE path);

rb_encoding *rb_utf8_encoding(void);
rb_encoding *rb_usascii_encoding(void);
rb_encoding *rb_ascii8bit_encoding(void);
rb_encoding *rb_default_internal_encoding(void);
rb_encoding *rb_default_external_encoding(void);
int          rb_utf8_encindex(void);
int          rb_usascii_encindex(void);
int          rb_ascii8bit_encindex(void);
int          rb_enc_get_index(VALUE obj);
int          rb_to_encoding_index(VALUE enc);
int          rb_enc_find_index(const char *name);
void         rb_enc_associate_index(VALUE obj, int idx);
VALUE        rb_enc_str_new(const char *ptr, long len, rb_encoding *enc);

int           rb_encoding_get(VALUE str);
rb_encoding  *rb_enc_from_index(int idx);
rb_encoding  *rb_enc_get(VALUE obj);
unsigned int  rb_enc_codepoint_len(const char *p, const char *e, int *len_p, rb_encoding *enc);
int           rb_isspace(unsigned int c);
char         *rb_enc_left_char_head(const char *str, const char *start, const char *end, rb_encoding *enc);

void         *xmalloc(size_t size);
void         *xcalloc(size_t n, size_t size);
void         *xrealloc(void *ptr, size_t size);
void          xfree(void *ptr);

#define RUBY_API_VERSION_CODE 30200

#ifdef __cplusplus
}
#endif

#endif
