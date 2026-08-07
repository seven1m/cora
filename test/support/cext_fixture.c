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

void Init_fixture(void)
{
    VALUE mCoraCExt = rb_define_module("CoraCExt");
    rb_define_module_function(mCoraCExt, "simple_yield", cext_simple_yield, 1);
    rb_define_module_function(mCoraCExt, "call_to_s", cext_call_to_s, 1);
    rb_define_module_function(mCoraCExt, "yield_nlr", cext_yield_nlr, 1);
    rb_define_module_function(mCoraCExt, "funcall_nlr", cext_funcall_nlr, 1);
    rb_define_module_function(mCoraCExt, "deep_nlr", cext_deep_nlr, 1);
    rb_define_module_function(mCoraCExt, "yield_next_then_value", cext_yield_next_then_value, 1);
    rb_define_module_function(mCoraCExt, "yield_break", cext_yield_break, 1);
    rb_define_module_function(mCoraCExt, "yield_break_then_value", cext_yield_break_then_value, 1);
    rb_define_module_function(mCoraCExt, "yield_next_then_call_to_s", cext_yield_next_then_call_to_s, 1);

    rb_define_method(rb_cString, "cora_cext_test", cora_cext_test, 0);
    rb_define_method(rb_cString, "cext_yield", cext_simple_yield, 1);
}
