#include "ruby.h"

static VALUE
cora_cext_test(VALUE str)
{
    (void)str;
    return Qtrue;
}

void Init_fixture(void)
{
    rb_define_method(rb_cString, "cora_cext_test", cora_cext_test, 0);
}
