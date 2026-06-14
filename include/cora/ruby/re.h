#include "../ruby.h"

#ifndef USE_CAPTURE_HISTORY
#define USE_CAPTURE_HISTORY
#endif

#include "oniguruma.h"

OnigPosition rb_reg_onig_match(
    VALUE re,
    VALUE str,
    OnigPosition (*match)(regex_t *reg, VALUE str, struct re_registers *regs, void *args),
    void *args,
    struct re_registers *regs
);

#define rb_reg_region_copy(dst, src) (onig_region_copy((dst), (src)), 0)
OnigRegex cora_rregexp_ptr(VALUE regexp);
#define RREGEXP_PTR(obj) cora_rregexp_ptr(obj)
