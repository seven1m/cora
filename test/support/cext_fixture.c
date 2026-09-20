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

static const rb_data_type_t cora_cext_data_type = {
    .wrap_struct_name = "CoraCExtData",
    .function = {
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
    rb_define_module_function(mCoraCExt, "string_value_cstr_length", cext_string_value_cstr_length, 1);
    rb_define_module_function(mCoraCExt, "class_of", cext_class_of, 1);
    rb_define_module_function(mCoraCExt, "obj_class", cext_obj_class, 1);
    rb_define_module_function(mCoraCExt, "ivar_access", cext_ivar_access, 1);
    rb_define_module_function(mCoraCExt, "array_mutation", cext_array_mutation, 0);
    rb_define_module_function(mCoraCExt, "undef_class_new", cext_undef_class_new, 1);
    rb_define_module_function(mCoraCExt, "scan_keywords", cext_scan_keywords, -1);

    rb_define_method(rb_cString, "cora_cext_test", cora_cext_test, 0);
    rb_define_method(rb_cString, "cext_yield", cext_simple_yield, 1);
}
