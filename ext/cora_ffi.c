#include "ruby.h"

#include <dlfcn.h>
#include <ffi.h>
#include <stdint.h>

#define MAX_FFI_ARGS 32

typedef union {
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
    for (long index = 0; index < count; index++) {
        VALUE type_name = rb_ary_entry(type_names, index);
        VALUE argument = rb_ary_entry(arguments, index);
        const char *name = rb_string_value_cstr(&type_name);
        types[index] = ffi_type_for(name);
        if (types[index] == &ffi_type_void) rb_raise(rb_eArgError, "void is not an argument type");

        if (types[index] == &ffi_type_sint32) {
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
            values[index].pointer = strcmp(name, "string") == 0
                ? (void *)rb_string_value_cstr(&argument)
                : (NIL_P(argument) ? NULL : (void *)(uintptr_t)NUM2LONG(argument));
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
    if (result_type == &ffi_type_void) return Qnil;
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

void
Init_cora_ffi(void)
{
    VALUE module = rb_define_module("CoraFFI");
    rb_define_module_function(module, "open", ffi_open, 1);
    rb_define_module_function(module, "symbol", ffi_symbol, 2);
    rb_define_module_function(module, "call", ffi_call_function, 4);
}
