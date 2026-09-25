#include "ruby.h"

static VALUE
cora_cext_test(VALUE str)
{
    (void)str;
    return Qtrue;
}

// Simple yield test (no NLR)
static VALUE
cext_simple_yield(VALUE self, VALUE arg)
{
    (void)self;
    return rb_yield(arg);
}

// Non-local return test: yields to a block, if the block does `return`,
// control should never reach the line after rb_yield.
static VALUE
cext_yield_nlr(VALUE self, VALUE arg)
{
    (void)self;
    rb_yield(arg);
    return rb_str_new2("should-not-return-this");
}

static VALUE
cext_funcall_nlr(VALUE self, VALUE obj)
{
    (void)self;
    return rb_funcall(obj, rb_intern("call"), 0);
}

// A newly raised exception or throw must skip the code after rb_funcall.
// A pre-existing unwind being processed by an ensure must not.
static VALUE
cext_funcall_then_value(VALUE self, VALUE obj)
{
    (void)self;
    rb_funcall(obj, rb_intern("call"), 0);
    return rb_str_new2("continued");
}

static VALUE
cext_deep_nlr(VALUE self, VALUE obj)
{
    (void)self;
    return rb_funcall(obj, rb_intern("run"), 0);
}

// Test: call a method on obj without a block
static VALUE
cext_call_to_s(VALUE self, VALUE obj)
{
    (void)self;
    return rb_funcall(obj, rb_intern("to_s"), 0);
}

// Yield to a block that does `next`. The yielded value should flow back as
// the rb_yield return value. A subsequent rb_yield in the same C function
// must not be polluted by a stale non-local return value.
static VALUE
cext_yield_next_then_value(VALUE self, VALUE marker)
{
    (void)self;
    VALUE v = rb_yield(marker);
    return rb_funcall(v, rb_intern("to_s"), 0);
}

// Yield to a block that does `break`. The block should return the break
// value to the C side; `next` semantics must not leak as a non-local return.
static VALUE
cext_yield_break(VALUE self, VALUE marker)
{
    (void)self;
    return rb_yield(marker);
}

// A block `break` must unwind past the C frame; code after rb_yield must not run.
static VALUE
cext_yield_break_then_value(VALUE self, VALUE marker)
{
    (void)self;
    rb_yield(marker);
    return rb_str_new2("continued-after-break");
}

// Yield to a block, then issue a fresh C-level call. If a previous `next`
// leaked into the C extension NLR state, this would surface as a stale value
// or a mis-dispatch. The C code uses the value returned from rb_yield for
// the subsequent rb_funcall so we exercise the C boundary cleanly.
static VALUE
cext_yield_next_then_call_to_s(VALUE self, VALUE marker)
{
    (void)self;
    VALUE v = rb_yield(marker);
    return rb_funcall(v, rb_intern("to_s"), 0);
}

static VALUE
cext_str_new_length(VALUE self, VALUE length)
{
    (void)self;
    return rb_str_new("abc", NUM2LONG(length));
}

static VALUE
cext_intern_length(VALUE self)
{
    (void)self;
    return ID2SYM(rb_intern2("abcdef", 3));
}

static VALUE
cext_static_string(VALUE self)
{
    (void)self;
    return rb_str_new_static("abcdef", 3);
}

typedef struct {
    int value;
} cora_cext_data;

typedef struct {
    VALUE retained;
} cora_cext_retainer;

static const rb_data_type_t cora_cext_data_type = {
    .wrap_struct_name = "CoraCExtData",
    .function = {
        .dfree = RUBY_DEFAULT_FREE,
    },
};

static void
cora_cext_retainer_mark(void *ptr)
{
    cora_cext_retainer *data = ptr;
    rb_gc_mark(data->retained);
}

static const rb_data_type_t cora_cext_retainer_type = {
    .wrap_struct_name = "CoraCExtRetainer",
    .function = {
        .dmark = cora_cext_retainer_mark,
        .dfree = RUBY_DEFAULT_FREE,
    },
};

static VALUE
cext_typed_data_round_trip(VALUE self)
{
    (void)self;
    VALUE object = rb_data_typed_object_zalloc(rb_cObject, sizeof(cora_cext_data), &cora_cext_data_type);
    cora_cext_data *data;
    TypedData_Get_Struct(object, cora_cext_data, &cora_cext_data_type, data);
    data->value = 42;
    return rb_assoc_new(INT2NUM(TYPE(object)), INT2NUM(data->value));
}

static VALUE
cext_typed_data_retain(VALUE self, VALUE retained)
{
    (void)self;
    cora_cext_retainer *data;
    VALUE object = TypedData_Make_Struct(rb_cObject, cora_cext_retainer, &cora_cext_retainer_type, data);
    RB_OBJ_WRITE(object, &data->retained, retained);
    return object;
}

static VALUE
cext_typed_data_retained(VALUE self, VALUE object)
{
    (void)self;
    cora_cext_retainer *data;
    TypedData_Get_Struct(object, cora_cext_retainer, &cora_cext_retainer_type, data);
    return data->retained;
}

static VALUE
cext_string_value_cstr_length(VALUE self, VALUE string)
{
    (void)self;
    return SIZET2NUM(strlen(StringValueCStr(string)));
}

static VALUE
cext_class_of(VALUE self, VALUE object)
{
    (void)self;
    return CLASS_OF(object);
}

static VALUE
cext_obj_class(VALUE self, VALUE object)
{
    (void)self;
    return rb_obj_class(object);
}

static VALUE
cext_ivar_access(VALUE self, VALUE object)
{
    (void)self;
    rb_iv_set(object, "@value", INT2NUM(42));
    return rb_ary_new3(3,
        rb_iv_get(object, "@value"),
        rb_ivar_defined(object, rb_intern("@value")) ? Qtrue : Qfalse,
        rb_ivar_defined(object, rb_intern("@missing")) ? Qtrue : Qfalse);
}

static VALUE
cext_array_mutation(VALUE self)
{
    (void)self;
    VALUE array = rb_ary_new3(3, INT2NUM(1), INT2NUM(2), INT2NUM(1));
    VALUE deleted = rb_ary_delete(array, INT2NUM(1));
    rb_ary_store(array, 2, INT2NUM(4));
    return rb_assoc_new(deleted, array);
}

static VALUE
cext_call_helpers(VALUE self, VALUE object)
{
    VALUE args = rb_ary_new3(1, INT2NUM(7));
    VALUE applied = rb_apply(object, rb_intern("+"), args);
    VALUE block_result = rb_block_given_p() ? rb_funcall(rb_block_proc(), rb_intern("call"), 1, applied) : Qnil;
    VALUE name = rb_str_new2(rb_class2name(CLASS_OF(object)));
    rb_str_buf_cat(name, "!", 1);
    return rb_ary_new3(2, block_result, name);
}

static VALUE
cext_exception_message(VALUE self)
{
    (void)self;
    VALUE exception = rb_exc_new2(rb_eRuntimeError, "from C");
    return rb_funcall(exception, rb_intern("message"), 0);
}

static VALUE
cext_exception_ivar_message(VALUE self)
{
    (void)self;
    VALUE exception = rb_exc_new2(rb_eRuntimeError, "original");
    rb_iv_set(exception, "mesg", rb_str_new_cstr("updated"));
    return exception;
}

static VALUE
cext_path_to_class(VALUE self, VALUE path)
{
    (void)self;
    return rb_path_to_class(path);
}

static VALUE
cext_integer_pack(VALUE self, VALUE integer)
{
    (void)self;
    int64_t packed = 0;
    int status = rb_integer_pack(integer, &packed, 1, sizeof(packed), 0,
        INTEGER_PACK_NATIVE_BYTE_ORDER | INTEGER_PACK_2COMP);
    char buffer[32];
    snprintf(buffer, sizeof(buffer), "%lld", (long long)packed);
    return rb_assoc_new(INT2NUM(status), rb_str_new_cstr(buffer));
}

static VALUE
cext_string_encoding_helpers(VALUE self)
{
    (void)self;
    VALUE joined = rb_str_plus(rb_str_new_cstr("left"), rb_str_new_cstr("right"));
    VALUE encoded = rb_str_encode(joined, rb_enc_from_encoding(rb_utf8_encoding()), 0, Qnil);
    return rb_assoc_new(encoded, INT2NUM(rb_enc_get_index(encoded)));
}

static VALUE
cext_string_encoding_creation(VALUE self)
{
    (void)self;
    const char byte = (char)0x80;
    VALUE source = rb_enc_str_new(&byte, 1, rb_ascii8bit_encoding());
    VALUE copied = rb_str_new(&byte, 1);
    rb_enc_copy(copied, source);
    return rb_assoc_new(source, copied);
}

static VALUE
cext_string_value(VALUE self, VALUE string)
{
    (void)self;
    StringValue(string);
    return string;
}

static VALUE
cext_undef_class_new(VALUE self, VALUE klass)
{
    (void)self;
    rb_undef_method(CLASS_OF(klass), "new");
    return Qnil;
}

static VALUE
cext_scan_keywords(int argc, VALUE *argv, VALUE self)
{
    (void)self;
    VALUE required, optional, keywords;
    int positional = rb_scan_args(argc, argv, "11:", &required, &optional, &keywords);
    return rb_ary_new3(4, INT2NUM(positional), required, optional, keywords);
}

static VALUE
cext_check_array_type(VALUE self, VALUE obj)
{
    (void)self;
    Check_Type(obj, T_ARRAY);
    return Qtrue;
}

void Init_fixture(void)
{
    VALUE mCoraCExt = rb_define_module("CoraCExt");
    rb_define_const(mCoraCExt, "FIXTURE_VALUE", INT2NUM(42));
    rb_define_module_function(mCoraCExt, "simple_yield", cext_simple_yield, 1);
    rb_define_module_function(mCoraCExt, "call_to_s", cext_call_to_s, 1);
    rb_define_module_function(mCoraCExt, "yield_nlr", cext_yield_nlr, 1);
    rb_define_module_function(mCoraCExt, "funcall_nlr", cext_funcall_nlr, 1);
    rb_define_module_function(mCoraCExt, "funcall_then_value", cext_funcall_then_value, 1);
    rb_define_module_function(mCoraCExt, "deep_nlr", cext_deep_nlr, 1);
    rb_define_module_function(mCoraCExt, "yield_next_then_value", cext_yield_next_then_value, 1);
    rb_define_module_function(mCoraCExt, "yield_break", cext_yield_break, 1);
    rb_define_module_function(mCoraCExt, "yield_break_then_value", cext_yield_break_then_value, 1);
    rb_define_module_function(mCoraCExt, "yield_next_then_call_to_s", cext_yield_next_then_call_to_s, 1);
    rb_define_module_function(mCoraCExt, "str_new_length", cext_str_new_length, 1);
    rb_define_module_function(mCoraCExt, "intern_length", cext_intern_length, 0);
    rb_define_module_function(mCoraCExt, "static_string", cext_static_string, 0);
    rb_define_module_function(mCoraCExt, "typed_data_round_trip", cext_typed_data_round_trip, 0);
    rb_define_module_function(mCoraCExt, "typed_data_retain", cext_typed_data_retain, 1);
    rb_define_module_function(mCoraCExt, "typed_data_retained", cext_typed_data_retained, 1);
    rb_define_module_function(mCoraCExt, "string_value_cstr_length", cext_string_value_cstr_length, 1);
    rb_define_module_function(mCoraCExt, "class_of", cext_class_of, 1);
    rb_define_module_function(mCoraCExt, "obj_class", cext_obj_class, 1);
    rb_define_module_function(mCoraCExt, "ivar_access", cext_ivar_access, 1);
    rb_define_module_function(mCoraCExt, "array_mutation", cext_array_mutation, 0);
    rb_define_module_function(mCoraCExt, "call_helpers", cext_call_helpers, 1);
    rb_define_module_function(mCoraCExt, "exception_message", cext_exception_message, 0);
    rb_define_module_function(mCoraCExt, "exception_ivar_message", cext_exception_ivar_message, 0);
    rb_define_module_function(mCoraCExt, "path_to_class", cext_path_to_class, 1);
    rb_define_module_function(mCoraCExt, "integer_pack", cext_integer_pack, 1);
    rb_define_module_function(mCoraCExt, "string_encoding_helpers", cext_string_encoding_helpers, 0);
    rb_define_module_function(mCoraCExt, "string_encoding_creation", cext_string_encoding_creation, 0);
    rb_define_module_function(mCoraCExt, "string_value", cext_string_value, 1);
    rb_define_module_function(mCoraCExt, "undef_class_new", cext_undef_class_new, 1);
    rb_define_module_function(mCoraCExt, "scan_keywords", cext_scan_keywords, -1);
    rb_define_module_function(mCoraCExt, "check_array_type", cext_check_array_type, 1);

    rb_define_method(rb_cString, "cora_cext_test", cora_cext_test, 0);
    rb_define_method(rb_cString, "cext_yield", cext_simple_yield, 1);
}
