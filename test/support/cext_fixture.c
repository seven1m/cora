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

void Init_fixture(void)
{
    VALUE mCoraCExt = rb_define_module("CoraCExt");
    rb_define_module_function(mCoraCExt, "simple_yield", cext_simple_yield, 1);
    rb_define_module_function(mCoraCExt, "call_to_s", cext_call_to_s, 1);
    rb_define_module_function(mCoraCExt, "yield_nlr", cext_yield_nlr, 1);
    rb_define_module_function(mCoraCExt, "funcall_nlr", cext_funcall_nlr, 1);
    rb_define_module_function(mCoraCExt, "deep_nlr", cext_deep_nlr, 1);

    rb_define_method(rb_cString, "cora_cext_test", cora_cext_test, 0);
    rb_define_method(rb_cString, "cext_yield", cext_simple_yield, 1);
}
