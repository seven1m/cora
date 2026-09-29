#include "ruby.h"

#include <dlfcn.h>
#include <ffi.h>
#include <stdint.h>

#define MAX_FFI_ARGS 32

typedef union {
    uint8_t uint8;
    int32_t sint32;
    uint32_t uint32;
    int64_t sint64;
    uint64_t uint64;
    double floating;
    void *pointer;
} ffi_value;

static ffi_type *
ffi_type_for(const char *name)
{
    if (strcmp(name, "void") == 0) return &ffi_type_void;
    if (strcmp(name, "bool") == 0) return &ffi_type_uint8;
    if (strcmp(name, "int") == 0 || strcmp(name, "sint32") == 0) return &ffi_type_sint32;
    if (strcmp(name, "uint32") == 0) return &ffi_type_uint32;
    if (strcmp(name, "long") == 0 || strcmp(name, "sint64") == 0) return &ffi_type_sint64;
    if (strcmp(name, "size_t") == 0 || strcmp(name, "uint64") == 0) return &ffi_type_uint64;
    if (strcmp(name, "double") == 0) return &ffi_type_double;
    if (strcmp(name, "pointer") == 0 || strcmp(name, "string") == 0) return &ffi_type_pointer;
    rb_raise(rb_eArgError, "unsupported FFI type: %s", name);
    return NULL;
}

static VALUE
ffi_open(VALUE self, VALUE path)
{
    (void)self;
    void *handle = dlopen(NIL_P(path) ? NULL : rb_string_value_cstr(&path), RTLD_NOW | RTLD_LOCAL);
    if (handle == NULL) rb_raise(rb_eLoadError, "%s", dlerror());
    return SIZET2NUM((uintptr_t)handle);
}

static VALUE
ffi_symbol(VALUE self, VALUE handle_value, VALUE name)
{
    (void)self;
    void *handle = (void *)(uintptr_t)NUM2LONG(handle_value);
    dlerror();
    void *symbol = dlsym(handle, rb_string_value_cstr(&name));
    const char *error = dlerror();
    if (error != NULL) rb_raise(rb_eLoadError, "%s", error);
    return SIZET2NUM((uintptr_t)symbol);
}

static VALUE
ffi_call_function(VALUE self, VALUE address, VALUE return_name, VALUE type_names, VALUE arguments)
{
    (void)self;
    long count = rb_array_len(type_names);
    if (count != rb_array_len(arguments)) rb_raise(rb_eArgError, "FFI argument count mismatch");
    if (count > MAX_FFI_ARGS) rb_raise(rb_eArgError, "too many FFI arguments");

    ffi_type *types[MAX_FFI_ARGS];
    ffi_value values[MAX_FFI_ARGS];
    void *pointers[MAX_FFI_ARGS];
    char *temporary_strings[MAX_FFI_ARGS] = {0};
    for (long index = 0; index < count; index++) {
        VALUE type_name = rb_ary_entry(type_names, index);
        VALUE argument = rb_ary_entry(arguments, index);
        const char *name = rb_string_value_cstr(&type_name);
        types[index] = ffi_type_for(name);
        if (types[index] == &ffi_type_void) rb_raise(rb_eArgError, "void is not an argument type");

        if (types[index] == &ffi_type_uint8) {
            values[index].uint8 = RTEST(argument) ? 1 : 0;
            pointers[index] = &values[index].uint8;
        } else if (types[index] == &ffi_type_sint32) {
            values[index].sint32 = (int32_t)NUM2LONG(argument);
            pointers[index] = &values[index].sint32;
        } else if (types[index] == &ffi_type_uint32) {
            values[index].uint32 = (uint32_t)NUM2LONG(argument);
            pointers[index] = &values[index].uint32;
        } else if (types[index] == &ffi_type_sint64) {
            values[index].sint64 = (int64_t)NUM2LONG(argument);
            pointers[index] = &values[index].sint64;
        } else if (types[index] == &ffi_type_uint64) {
            values[index].uint64 = (uint64_t)NUM2LONG(argument);
            pointers[index] = &values[index].uint64;
        } else if (types[index] == &ffi_type_double) {
            values[index].floating = NUM2DBL(argument);
            pointers[index] = &values[index].floating;
        } else {
            if ((strcmp(name, "string") == 0 || strcmp(name, "pointer") == 0) && TYPE(argument) == T_STRING) {
                long length = RSTRING_LEN(argument);
                char *copy = malloc((size_t)length + 1);
                if (copy == NULL) rb_raise(rb_eNoMemError, "out of memory");
                memcpy(copy, RSTRING_PTR(argument), (size_t)length);
                copy[length] = '\0';
                temporary_strings[index] = copy;
                values[index].pointer = copy;
            } else {
                values[index].pointer = NIL_P(argument) ? NULL : (void *)(uintptr_t)NUM2LONG(argument);
            }
            pointers[index] = &values[index].pointer;
        }
    }

    const char *result_name = rb_string_value_cstr(&return_name);
    ffi_type *result_type = ffi_type_for(result_name);
    ffi_cif cif;
    if (ffi_prep_cif(&cif, FFI_DEFAULT_ABI, (unsigned int)count, result_type, types) != FFI_OK) {
        rb_raise(rb_eArgError, "cannot prepare FFI call");
    }

    ffi_value result = {0};
    ffi_call(&cif, FFI_FN((void *)(uintptr_t)NUM2LONG(address)), &result, pointers);
    for (long index = 0; index < count; index++) free(temporary_strings[index]);
    if (result_type == &ffi_type_void) return Qnil;
    if (result_type == &ffi_type_uint8) return result.uint8 ? Qtrue : Qfalse;
    if (result_type == &ffi_type_sint32) return LONG2NUM(result.sint32);
    if (result_type == &ffi_type_uint32) return SIZET2NUM(result.uint32);
    if (result_type == &ffi_type_sint64) return LONG2NUM(result.sint64);
    if (result_type == &ffi_type_uint64) return SIZET2NUM(result.uint64);
    if (result_type == &ffi_type_double) return rb_float_new(result.floating);
    if (strcmp(result_name, "string") == 0) {
        return result.pointer == NULL ? Qnil : rb_str_new2((const char *)result.pointer);
    }
    return result.pointer == NULL ? Qnil : SIZET2NUM((uintptr_t)result.pointer);
}

static VALUE
ffi_alloc(VALUE self, VALUE size_value, VALUE clear_value)
{
    (void)self;
    long size = NUM2LONG(size_value);
    if (size < 0) rb_raise(rb_eArgError, "negative FFI allocation size");
    void *pointer = RTEST(clear_value) ? calloc((size_t)size, 1) : malloc((size_t)size);
    if (pointer == NULL) rb_raise(rb_eNoMemError, "out of memory");
    return SIZET2NUM((uintptr_t)pointer);
}

static VALUE
ffi_free(VALUE self, VALUE address)
{
    (void)self;
    free((void *)(uintptr_t)NUM2LONG(address));
    return Qnil;
}

static VALUE
ffi_read(VALUE self, VALUE address, VALUE length_value)
{
    (void)self;
    const char *pointer = (const char *)(uintptr_t)NUM2LONG(address);
    if (pointer == NULL) rb_raise(rb_eArgError, "null FFI pointer");
    if (NIL_P(length_value)) return rb_str_new2(pointer);
    long length = NUM2LONG(length_value);
    if (length < 0) rb_raise(rb_eArgError, "negative FFI read length");
    return rb_str_new(pointer, length);
}

static VALUE
ffi_write(VALUE self, VALUE address, VALUE string, VALUE length_value)
{
    (void)self;
    long length = NUM2LONG(length_value);
    if (length < 0 || length > RSTRING_LEN(string)) rb_raise(rb_eArgError, "invalid FFI write length");
    memcpy((void *)(uintptr_t)NUM2LONG(address), RSTRING_PTR(string), (size_t)length);
    return string;
}

static VALUE
ffi_put_char(VALUE self, VALUE address, VALUE offset_value, VALUE byte_value)
{
    (void)self;
    long offset = NUM2LONG(offset_value);
    if (offset < 0) rb_raise(rb_eArgError, "negative FFI offset");
    char *pointer = (char *)(uintptr_t)NUM2LONG(address);
    pointer[offset] = (char)NUM2LONG(byte_value);
    return byte_value;
}

void
Init_cora_ffi(void)
{
    VALUE module = rb_define_module("CoraFFI");
    rb_define_module_function(module, "open", ffi_open, 1);
    rb_define_module_function(module, "symbol", ffi_symbol, 2);
    rb_define_module_function(module, "call", ffi_call_function, 4);
    rb_define_module_function(module, "alloc", ffi_alloc, 2);
    rb_define_module_function(module, "free", ffi_free, 1);
    rb_define_module_function(module, "read", ffi_read, 2);
    rb_define_module_function(module, "write", ffi_write, 3);
    rb_define_module_function(module, "put_char", ffi_put_char, 3);
}
