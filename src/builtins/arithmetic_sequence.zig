const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const float_builtin = @import("float.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Value = value.Value;

pub fn toF64(vm: *VM, number: Value) VMError!f64 {
    if (number.isFloat()) return number.toFloatObject().val;
    if (number.isInteger() or number.isBigInteger()) return number.integerToF64();
    return (try float_builtin.coerceArgToFloat(vm, number)).toFloatObject().val;
}

pub fn floatStepSize(begin: f64, end: f64, step: f64, exclude_end: bool) f64 {
    if (step == 0) return std.math.inf(f64);
    if (std.math.isInf(step)) return if (if (step > 0) begin <= end else begin >= end) 1 else 0;
    var count = (end - begin) / step;
    const epsilon = std.math.floatEps(f64);
    const tolerance = @min(0.5, (@abs(begin) + @abs(end) + @abs(end - begin)) / @abs(step) * epsilon);
    if (exclude_end) {
        if (count <= 0) return 0;
        count = if (count < 1) 0 else @floor(count - tolerance);
        const candidate = (count + 1) * step + begin;
        if ((begin < end and candidate < end) or (begin > end and candidate > end)) count += 1;
    } else {
        if (count < 0) return 0;
        count = @floor(count + tolerance);
        const candidate = (count + 1) * step + begin;
        if ((begin < end and candidate <= end) or (begin > end and candidate >= end)) count += 1;
    }
    return count + 1;
}

pub fn intervalSize(vm: *VM, begin: Value, end: Value, step: Value, exclude_end: bool) VMError!Value {
    var args = [_]Value{Value.integer(0)};
    const positive = (try vm.callMethodByName(step, ">", &args, null)).isTruthy();
    const zero = (try vm.callMethodByName(step, "==", &args, null)).isTruthy();
    if (zero or end.isNil()) return vm.newFloat(std.math.inf(f64));
    if (begin.isFloat() or end.isFloat() or step.isFloat()) {
        const count = floatStepSize(try toF64(vm, begin), try toF64(vm, end), try toF64(vm, step), exclude_end);
        if (count <= 0) return Value.integer(0);
        if (std.math.isInf(count)) return vm.newFloat(count);
        return vm.integerFromFloat(count);
    }
    const comparison = if (positive) ">" else "<";
    args[0] = end;
    if ((try vm.callMethodByName(begin, comparison, &args, null)).isTruthy()) return Value.integer(0);
    args[0] = begin;
    const delta = try vm.callMethodByName(end, "-", &args, null);
    args[0] = step;
    var count = try vm.callMethodByName(delta, "div", &args, null);
    var include_last = !exclude_end;
    if (!include_last) {
        const offset = try vm.callMethodByName(count, "*", &args, null);
        args[0] = offset;
        const last = try vm.callMethodByName(begin, "+", &args, null);
        args[0] = last;
        include_last = (try vm.callMethodByName(end, comparison, &args, null)).isTruthy();
    }
    if (include_last) {
        args[0] = Value.integer(1);
        count = try vm.callMethodByName(count, "+", &args, null);
    }
    return count;
}
