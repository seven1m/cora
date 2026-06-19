#ifndef CORA_RUBY_H
#define CORA_RUBY_H

#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdbool.h>
#include <limits.h>
#include <string.h>
#include <ctype.h>
#include <sys/time.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef uint64_t VALUE;
typedef unsigned long ID;
typedef struct { int _; } rb_encoding;

#ifndef HAVE_STDBOOL_H
#define HAVE_STDBOOL_H 1
#endif

#ifndef _
#define _(args) args
#endif

#define Qfalse ((VALUE)0x00)
#define Qtrue  ((VALUE)0x02)
#define Qnil   ((VALUE)0x04)
#define Qundef ((VALUE)0x06)
#define RUBY_Qnil Qnil

#define RUBY_IMMEDIATE_MASK 0x03
#define RUBY_FIXNUM_FLAG    0x01
#define RUBY_FLONUM_MASK    0x02

#define IMMEDIATE_P(x)   ((((VALUE)(x)) & RUBY_FIXNUM_FLAG) || ((VALUE)(x)) <= Qundef)
#define FIXNUM_P(x)      ((((VALUE)(x)) & RUBY_FIXNUM_FLAG) != 0)
#define NIL_P(x)         ((x) == Qnil)
#define RB_NIL_P(x)      NIL_P(x)
#define RTEST(x)         ((x) & ~Qnil)
#define RB_LIKELY(x)     (x)
#define RB_UNLIKELY(x)   (x)
#define RB_SPECIAL_CONST_P(obj) IMMEDIATE_P(obj)
#define RB_FIXNUM_P(obj) FIXNUM_P(obj)
#define RB_FLONUM_P(obj) 0
#define RB_STATIC_SYM_P(obj) (TYPE(obj) == T_SYMBOL)
#define RB_SYMBOL_P(obj) (TYPE(obj) == T_SYMBOL)
#define RB_BUILTIN_TYPE(obj) TYPE(obj)
#define RBASIC_CLASS(obj) rb_class_of(obj)
#define RB_OBJ_FROZEN_RAW(obj) rb_obj_frozen_p(obj)

#define INT2FIX(x) (((VALUE)(x)) << 1 | RUBY_FIXNUM_FLAG)
#define FIX2LONG(x) ((long)((x) >> 1))
#define FIX2INT(x)  ((int)FIX2LONG(x))
#define LONG2FIX(x) INT2FIX(x)

#define FIXNUM_MAX ((VALUE)(LONG_MAX >> 1))
#define FIXNUM_MIN ((VALUE)(LONG_MIN >> 1))
#define LL2NUM(x) LONG2NUM((long)(x))
#define ULL2NUM(x) ULONG2NUM((unsigned long)(x))

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
#define RSTRING_GETMEM(str, ptrvar, lenvar) \
    ((ptrvar) = RSTRING_PTR(str),           \
     (lenvar) = RSTRING_LEN(str))
#define ENCODING_GET(str) rb_encoding_get(str)
#define RB_ENCODING_GET(str) ENCODING_GET(str)
#define RB_ENCODING_GET_INLINED(str) ENCODING_GET(str)
#define ENCODING_GET_INLINED(str) ENCODING_GET(str)

#define RB_INTEGER_TYPE_P(obj) (FIXNUM_P(obj) || TYPE(obj) == T_BIGNUM)
#define ENC_CODERANGE_7BIT 1
#define ENC_CODERANGE_VALID 2
#define RUBY_ENC_CODERANGE_UNKNOWN 0
#define RB_ENC_CODERANGE(str) rb_enc_str_coderange(str)

#define ID2SYM(id) ((VALUE)(id))
#define SYM2ID(sym) ((ID)(sym))

#define HAVE_GMTIME_R 1
#define HAVE_LOCALTIME_R 1

VALUE rb_hash(VALUE obj);
#define DBL2NUM(v) rb_float_new(v)
VALUE rb_float_new(double v);
VALUE rb_enc_str_asciicompat_p(VALUE str);
double rb_cstr_to_dbl(const char *str, int badcheck);

#define NUM2SIZET(v) ((size_t)NUM2LONG(v))
#define PRI_SIZE_PREFIX "l"
#define PRIsVALUE "s"

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

#define RUBY_EXTERN extern
#define ISDIGIT(c) isdigit(c)
#define ISLOWER(c) islower(c)
#define ISUPPER(c) isupper(c)
#define TOUPPER(c) toupper(c)
#define TOLOWER(c) tolower(c)
#define STRTOUL strtoul
#define rb_isdigit(c) isdigit((unsigned char)(c))
#define rb_isxdigit(c) isxdigit((unsigned char)(c))
#define rb_isalpha(c) isalpha((unsigned char)(c))
#define rb_tolower(c) tolower((unsigned char)(c))
#define MEMCPY(dest, src, type, n) memcpy((dest), (src), sizeof(type) * (n))
#define MEMMOVE(dest, src, type, n) memmove((dest), (src), sizeof(type) * (n))
#define ST_CONTINUE 0
#define UNREACHABLE ((void)0)
#define UNREACHABLE_RETURN(val) return (val)

int rb_type(VALUE obj);
#define TYPE(obj) rb_type(obj)
#define RB_TYPE_P(obj, type) (rb_type(obj) == (type))

#define RB_OBJ_WRITE(a, b, c) ((void)(a), ((uintptr_t)(b) <= (uintptr_t)Qundef ? (void)0 : (*(VALUE *)(b) = (VALUE)(c))))
#define RB_OBJ_WRITTEN(a, b, c) RB_OBJ_WRITE(a, b, c)
#define RB_OBJ_FREEZE(obj) rb_obj_freeze(obj)

#define RETURN_ENUMERATOR(obj, argc, argv) ((void)0)

#define CLASS_OF(obj) rb_class_of(obj)
#define RHASH_SIZE(obj) rb_hash_size(obj)
#define RSTRUCT_GET(obj, idx) rb_struct_get(obj, idx)

#define SIZEOF_LONG (sizeof(long))
#define DECIMAL_SIZE_OF_BITS(b) (((b) * 643 + 2136) / 2137)

double rb_float_value(VALUE v);
#define RFLOAT_VALUE(v) rb_float_value(v)
double rb_num2dbl(VALUE v);
#define NUM2DBL(v) rb_num2dbl(v)

VALUE rb_usascii_str_new(const char *ptr, long len);

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
        void (*dcompact)(void*);
        void (*handle_weak_references)(void*);
        void *reserved[7];
    } function;
    const void *parent;
    void *data;
    VALUE flags;
} rb_data_type_t;

#define RUBY_TYPED_DEFAULT_FREE NULL
#define RUBY_DEFAULT_FREE RUBY_TYPED_DEFAULT_FREE
#define RUBY_TYPED_NEVER_FREE   ((void (*)(void *))(-1))
#define RUBY_TYPED_FREE_IMMEDIATELY  0
#define RUBY_TYPED_WB_PROTECTED  1
#define RUBY_TYPED_FROZEN_SHAREABLE 0
#define RUBY_TYPED_EMBEDDABLE 0

VALUE TypedData_Wrap_Struct(VALUE klass, const rb_data_type_t *type, void *data);
VALUE rb_data_typed_object_alloc(VALUE klass, const rb_data_type_t *type);
void *Check_TypedStruct(VALUE obj, const rb_data_type_t *type);
#define TypedData_Make_Struct(klass, type_name, type, data) \
    ((data) = (type_name *)calloc(1, sizeof(type_name)), \
     TypedData_Wrap_Struct(klass, type, data))
#define TypedData_Get_Struct(obj, type_name, type, data) \
    ((data) = (type_name *)Check_TypedStruct(obj, type))

#define RTYPEDDATA_DATA(obj) Check_TypedStruct(obj, NULL)
#define DATA_PTR(obj) Check_TypedStruct(obj, NULL)

void rb_data_set_typeddata(VALUE obj, void *data);

typedef struct { int basic; const rb_data_type_t *type; int typed_flag; void *data; } RTypedData;
#define RTYPEDDATA(obj) ((RTypedData *)(uintptr_t)(obj))

/* Check_Type */
void Check_Type(VALUE obj, int type);

/* functions */
char  *rb_string_ptr(VALUE str);
long   rb_string_len(VALUE str);
char  *rb_string_value_cstr(VALUE *ptr);
char  *rb_string_value_ptr(VALUE *ptr);
VALUE  rb_string_value(VALUE *ptr);
VALUE  rb_str_cat2(VALUE str, const char *ptr);
VALUE  rb_str_dump(VALUE str);
VALUE  rb_sprintf(const char *fmt, ...);
VALUE  rb_vsprintf(const char *fmt, va_list ap);
VALUE  rb_sym2str(VALUE symbol);
VALUE  rb_check_hash_type(VALUE obj);
int    rb_get_kwargs(VALUE keyword_hash, const ID *table, int required, int optional, VALUE *values);
void   rb_memerror(void);
long   rb_enc_strlen(const char *head, const char *tail, rb_encoding *enc);
int    rb_enc_mbclen(const char *p, const char *e, rb_encoding *enc);
rb_encoding *rb_enc_check(VALUE str1, VALUE str2);
long   rb_memsearch(const void *x, long m, const void *y, long n, rb_encoding *enc);
void   rb_must_asciicompat(VALUE obj);
void   rb_enc_raise(rb_encoding *enc, VALUE exc, const char *fmt, ...);
void   rb_str_modify(VALUE str);

VALUE  rb_str_new(const char *ptr, long len);
VALUE  rb_str_new_cstr(const char *ptr);
VALUE  rb_usascii_str_new(const char *ptr, long len);
VALUE  rb_str_new2(const char *ptr);
#define rb_str_new_cstr rb_str_new2
VALUE  rb_usascii_str_new_cstr(const char *ptr);
#define rb_usascii_str_new2 rb_usascii_str_new_cstr
VALUE  rb_enc_str_new(const char *ptr, long len, rb_encoding *enc);
VALUE  rb_utf8_str_new(const char *ptr, long len);
VALUE  rb_utf8_str_new_cstr(const char *ptr);
VALUE  rb_str_export_to_enc(VALUE str, rb_encoding *enc);
VALUE  rb_str_buf_new(long len);
void   rb_str_set_len(VALUE str, long len);
VALUE  rb_str_tmp_new(long len);
VALUE  rb_str_catf(VALUE str, const char *fmt, ...);
VALUE  rb_str_intern(VALUE str);
VALUE  rb_str_concat(VALUE str, VALUE str2);
VALUE  rb_str_substr(VALUE str, long beg, long len);
VALUE  rb_str_new_shared(VALUE str);
VALUE  rb_str_freeze(VALUE str);

VALUE  rb_ary_new(void);
VALUE  rb_ary_new3(long n, ...);
VALUE  rb_ary_new4(long n, const VALUE *elts);
VALUE  rb_ary_push(VALUE ary, VALUE item);
VALUE  rb_ary_new_from_values(long n, const VALUE *elts);

ID     rb_intern(const char *name);
VALUE  rb_const_get(VALUE klass, ID id);
VALUE  rb_const_get_at(VALUE klass, ID id);
void   rb_define_const(VALUE klass, const char *name, VALUE val);
int    rb_const_defined(VALUE klass, ID id);
void   rb_const_set(VALUE klass, ID id, VALUE val);
void   rb_alias(VALUE klass, ID dst, ID src);

VALUE  rb_funcall(VALUE recv, ID mid, int argc, ...);
VALUE  rb_funcallv(VALUE recv, ID mid, int argc, const VALUE *argv);
VALUE  rb_funcallv_public(VALUE recv, ID mid, int argc, const VALUE *argv);
#define rb_funcall3 rb_funcallv
VALUE  rb_proc_call_with_block(VALUE recv, int argc, const VALUE *argv, VALUE block);
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
VALUE  rb_exc_new_str(VALUE klass, VALUE str);
VALUE  rb_protect(VALUE (*proc)(VALUE), VALUE data, int *state);
VALUE  rb_ensure(VALUE (*b_proc)(VALUE), VALUE data1, VALUE (*e_proc)(VALUE), VALUE data2);
VALUE  rb_rescue(VALUE (*b_proc)(VALUE), VALUE data1, VALUE (*r_proc)(VALUE, VALUE), VALUE data2);
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
#define rb_path2class(path) rb_path_to_class(rb_str_new2(path))

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
VALUE        rb_enc_associate_index(VALUE obj, int idx);
VALUE        rb_enc_str_new(const char *ptr, long len, rb_encoding *enc);
int          rb_enc_str_coderange(VALUE obj);

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
void         *ruby_xrealloc2(void *ptr, size_t n, size_t size);

#include "ruby/util.h"
#include "ruby/missing.h"
#include "ruby/st.h"

#define RUBY_API_VERSION_CODE 30200

extern VALUE rb_cRational;
extern VALUE rb_cTime;
extern VALUE rb_mComparable;

VALUE rb_define_class(const char *name, VALUE super);
void  rb_include_module(VALUE klass, VALUE module);
void  rb_define_alias(VALUE klass, const char *name, const char *def);
VALUE rb_singleton_class(VALUE obj);
VALUE rb_obj_is_kind_of(VALUE obj, VALUE klass);
VALUE rb_cmpint(VALUE val, VALUE a, VALUE b);

VALUE rb_hash_new(void);
VALUE rb_hash_new_capa(long capa);
VALUE rb_hash_aref(VALUE hash, VALUE key);
VALUE rb_hash_aset(VALUE hash, VALUE key, VALUE val);
VALUE rb_hash_delete(VALUE hash, VALUE key);
long  rb_hash_size(VALUE hash);
int   rb_hash_foreach(VALUE hash, int (*func)(VALUE, VALUE, VALUE), VALUE arg);

VALUE rb_str_append(VALUE str, VALUE str2);
VALUE rb_str_cat(VALUE str, const char *ptr, long len);
VALUE rb_str_dup(VALUE str);
VALUE rb_str_to_inum(VALUE str, int base, int badcheck);
VALUE rb_str_subseq(VALUE str, long beg, long len);
VALUE rb_str_new_frozen(VALUE str);
long  rb_strlen_lit(const char *ptr);

VALUE rb_reg_new(const char *source, long len, int options);
VALUE rb_reg_nth_match(long nth, VALUE match);

void rb_warn(const char *fmt, ...);
int  rb_warning(const char *fmt, ...);

VALUE rb_ary_freeze(VALUE ary);
VALUE rb_ary_new2(long len);
VALUE rb_inspect(VALUE obj);
VALUE rb_class_name(VALUE klass);
VALUE rb_convert_type(VALUE obj, int type, const char *tname, const char *method);
VALUE rb_obj_hide(VALUE obj);
int   rb_proc_arity(VALUE proc);
VALUE rb_errinfo(void);
void  rb_set_errinfo(VALUE val);
void  rb_global_variable(VALUE *obj);
void  rb_gc_mark_movable(VALUE ptr);
VALUE rb_gc_location(VALUE ptr);
VALUE rb_io_write(VALUE io, VALUE str);
VALUE rb_io_flush(VALUE io);
int   rb_obj_frozen_p(VALUE obj);
VALUE rb_struct_get(VALUE obj, long idx);

VALUE rb_obj_freeze(VALUE obj);
void  rb_check_frozen(VALUE obj);
void  rb_check_arity(int argc, int min, int max);
void *rb_check_typeddata(VALUE obj, const void *data_type);
void  rb_gc_mark(VALUE ptr);
void  rb_gc_register_mark_object(VALUE obj);
VALUE rb_marshal_load(VALUE source);

VALUE rb_enc_copy(VALUE dest, VALUE src);
VALUE rb_enc_sprintf(rb_encoding *enc, const char *fmt, ...);
VALUE rb_str_format(int argc, const VALUE *argv, VALUE fmt);

void rb_sys_fail(const char *msg);
void rb_undef_method(VALUE klass, const char *name);
ID   rb_intern_const(const char *name);
VALUE rb_int_positive_pow(long x, unsigned long y);

VALUE rb_cstr_to_inum(const char *str, int base, int badcheck);
#define rb_cstr2inum(str, base) rb_cstr_to_inum((str), (base), 1)
int   rb_match_busy(VALUE match);
long  rb_memhash(const void *ptr, long len);

static inline int rb_long2int(long n) { return (int)n; }

VALUE rb_num_coerce_cmp(VALUE x, VALUE y, ID cmp);
VALUE rb_rational_new(VALUE num, VALUE den);
VALUE rb_rational_new1(VALUE num);
VALUE rb_rational_num(VALUE rat);
VALUE rb_rational_den(VALUE rat);
VALUE rb_rational_new2(VALUE num, VALUE den);

VALUE rb_backref_get(void);
void  rb_backref_set(VALUE val);
void  rb_category_warn(int category, const char *fmt, ...);
void  rb_copy_generic_ivar(VALUE clone, VALUE obj);

#ifdef __cplusplus
}
#endif

#endif
