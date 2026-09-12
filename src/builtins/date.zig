const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const Block = vm_mod.Block;
const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const date_name = try vm.intern("Date");
    if (vm.object_class.module.constants.contains(date_name)) return;

    const date_value = try vm.newClass(date_name, vm.object_class);
    const date_class = date_value.toClassObject();
    date_class.builtin_alloc_func = &builtinDateAllocate;
    try vm.setConstant(&vm.object_class.module, date_name, date_value);

    try date_class.module.constants.put(try vm.intern("ITALY"), .{ .value = Value.integer(2_299_161) });
    try date_class.module.constants.put(try vm.intern("ENGLAND"), .{ .value = Value.integer(2_361_222) });

    const datetime_name = try vm.intern("DateTime");
    const datetime_value = try vm.newClass(datetime_name, date_class);
    const datetime_class = datetime_value.toClassObject();
    datetime_class.builtin_alloc_func = &builtinDateTimeAllocate;
    try vm.setConstant(&vm.object_class.module, datetime_name, datetime_value);

    for ([_]*value.ClassObject{ date_class, datetime_class }) |class| {
        try class.module.methods.put(try vm.intern("inspect"), value.MethodEntry.builtin(&builtinDateInspect, .{ .exact = 0 }));
        try class.module.methods.put(try vm.intern("eql?"), value.MethodEntry.builtin(&builtinDateEql, .{ .exact = 1 }));
        try class.module.methods.put(try vm.intern("hash"), value.MethodEntry.builtin(&builtinDateHash, .{ .exact = 0 }));
    }

    const date_singleton = try vm.getOrCreateSingletonClass(date_value);
    const civil_entry = value.MethodEntry.builtin(&builtinDateCivil, .{ .variadic = 0 });
    try date_singleton.module.methods.put(try vm.intern("new"), civil_entry);
    try date_singleton.module.methods.put(try vm.intern("civil"), civil_entry);
    try date_singleton.module.methods.put(try vm.intern("jd"), value.MethodEntry.builtin(&builtinDateFromJd, .{ .variadic = 0 }));
    const valid_date_entry = value.MethodEntry.builtin(&builtinDateValidDate, .{ .variadic = 3 });
    try date_singleton.module.methods.put(try vm.intern("valid_date?"), valid_date_entry);
    try date_singleton.module.methods.put(try vm.intern("valid_civil?"), valid_date_entry);
    try date_singleton.module.methods.put(try vm.intern("valid_jd?"), value.MethodEntry.builtin(&builtinDateValidJd, .{ .variadic = 1 }));
    try date_singleton.module.methods.put(try vm.intern("gregorian_leap?"), value.MethodEntry.builtin(&builtinDateGregorianLeap, .{ .exact = 1 }));
    try date_singleton.module.methods.put(try vm.intern("julian_leap?"), value.MethodEntry.builtin(&builtinDateJulianLeap, .{ .exact = 1 }));

    try date_class.module.methods.put(try vm.intern("year"), value.MethodEntry.builtin(&builtinDateYear, .{ .exact = 0 }));
    const month_entry = value.MethodEntry.builtin(&builtinDateMonth, .{ .exact = 0 });
    try date_class.module.methods.put(try vm.intern("month"), month_entry);
    try date_class.module.methods.put(try vm.intern("mon"), month_entry);
    const day_entry = value.MethodEntry.builtin(&builtinDateDay, .{ .exact = 0 });
    try date_class.module.methods.put(try vm.intern("day"), day_entry);
    try date_class.module.methods.put(try vm.intern("mday"), day_entry);
    try date_class.module.methods.put(try vm.intern("jd"), value.MethodEntry.builtin(&builtinDateJd, .{ .exact = 0 }));
    try date_class.module.methods.put(try vm.intern("ajd"), value.MethodEntry.builtin(&builtinDateAjd, .{ .exact = 0 }));
    const mjd_entry = value.MethodEntry.builtin(&builtinDateMjd, .{ .exact = 0 });
    try date_class.module.methods.put(try vm.intern("mjd"), mjd_entry);
    try date_class.module.methods.put(try vm.intern("amjd"), mjd_entry);
    try date_class.module.methods.put(try vm.intern("ld"), value.MethodEntry.builtin(&builtinDateLd, .{ .exact = 0 }));
    try date_class.module.methods.put(try vm.intern("day_fraction"), value.MethodEntry.builtin(&builtinDateDayFraction, .{ .exact = 0 }));
    try date_class.module.methods.put(try vm.intern("yday"), value.MethodEntry.builtin(&builtinDateYday, .{ .exact = 0 }));
    try date_class.module.methods.put(try vm.intern("wday"), value.MethodEntry.builtin(&builtinDateWday, .{ .exact = 0 }));
    try date_class.module.methods.put(try vm.intern("cwyear"), value.MethodEntry.builtin(&builtinDateCwyear, .{ .exact = 0 }));
    try date_class.module.methods.put(try vm.intern("cweek"), value.MethodEntry.builtin(&builtinDateCweek, .{ .exact = 0 }));
    try date_class.module.methods.put(try vm.intern("cwday"), value.MethodEntry.builtin(&builtinDateCwday, .{ .exact = 0 }));
    try date_class.module.methods.put(try vm.intern("julian?"), value.MethodEntry.builtin(&builtinDateJulian, .{ .exact = 0 }));
    try date_class.module.methods.put(try vm.intern("gregorian?"), value.MethodEntry.builtin(&builtinDateGregorian, .{ .exact = 0 }));
    try date_class.module.methods.put(try vm.intern("succ"), value.MethodEntry.builtin(&builtinDateSucc, .{ .exact = 0 }));
    try date_class.module.methods.put(try vm.intern("next"), value.MethodEntry.builtin(&builtinDateSucc, .{ .exact = 0 }));
    try date_class.module.methods.put(try vm.intern("+"), value.MethodEntry.builtin(&builtinDateAdd, .{ .exact = 1 }));
    try date_class.module.methods.put(try vm.intern("-"), value.MethodEntry.builtin(&builtinDateSubtract, .{ .exact = 1 }));
    try date_class.module.methods.put(try vm.intern(">>"), value.MethodEntry.builtin(&builtinDateAddMonths, .{ .exact = 1 }));
    try date_class.module.methods.put(try vm.intern("<<"), value.MethodEntry.builtin(&builtinDateSubtractMonths, .{ .exact = 1 }));
    try date_class.module.methods.put(try vm.intern("next_day"), value.MethodEntry.builtin(&builtinDateNextDay, .{ .variadic = 0 }));
    try date_class.module.methods.put(try vm.intern("prev_day"), value.MethodEntry.builtin(&builtinDatePrevDay, .{ .variadic = 0 }));
    try date_class.module.methods.put(try vm.intern("<=>"), value.MethodEntry.builtin(&builtinDateCompare, .{ .exact = 1 }));
    const equal_entry = value.MethodEntry.builtin(&builtinDateEqual, .{ .exact = 1 });
    try date_class.module.methods.put(try vm.intern("=="), equal_entry);
    try date_class.module.methods.put(try vm.intern("==="), equal_entry);
}

const Civil = struct {
    year: i64,
    month: i64,
    day: i64,
};

fn gregorianLeap(year: i64) bool {
    return @mod(year, 4) == 0 and (@mod(year, 100) != 0 or @mod(year, 400) == 0);
}

fn julianLeap(year: i64) bool {
    return @mod(year, 4) == 0;
}

fn daysInMonth(year: i64, month: i64, gregorian: bool) i64 {
    return switch (month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => if (if (gregorian) gregorianLeap(year) else julianLeap(year)) 29 else 28,
        else => 0,
    };
}

fn gregorianToJd(year: i64, month: i64, day: i64) i64 {
    const a = @divFloor(14 - month, 12);
    const y = year + 4800 - a;
    const m = month + 12 * a - 3;
    return day + @divFloor(153 * m + 2, 5) + 365 * y + @divFloor(y, 4) - @divFloor(y, 100) + @divFloor(y, 400) - 32045;
}

fn julianToJd(year: i64, month: i64, day: i64) i64 {
    const a = @divFloor(14 - month, 12);
    const y = year + 4800 - a;
    const m = month + 12 * a - 3;
    return day + @divFloor(153 * m + 2, 5) + 365 * y + @divFloor(y, 4) - 32083;
}

fn jdToGregorian(jd: i64) Civil {
    const a = jd + 32044;
    const b = @divFloor(4 * a + 3, 146097);
    const c = a - @divFloor(146097 * b, 4);
    const d = @divFloor(4 * c + 3, 1461);
    const e = c - @divFloor(1461 * d, 4);
    const m = @divFloor(5 * e + 2, 153);
    return .{
        .year = 100 * b + d - 4800 + @divFloor(m, 10),
        .month = m + 3 - 12 * @divFloor(m, 10),
        .day = e - @divFloor(153 * m + 2, 5) + 1,
    };
}

fn jdToJulian(jd: i64) Civil {
    const c = jd + 32082;
    const d = @divFloor(4 * c + 3, 1461);
    const e = c - @divFloor(1461 * d, 4);
    const m = @divFloor(5 * e + 2, 153);
    return .{
        .year = d - 4800 + @divFloor(m, 10),
        .month = m + 3 - 12 * @divFloor(m, 10),
        .day = e - @divFloor(153 * m + 2, 5) + 1,
    };
}

fn civilToJd(year: i64, month: i64, day: i64, start: i64) ?i64 {
    if (month < 1 or month > 12 or day < 1) return null;
    const gregorian_jd = gregorianToJd(year, month, day);
    if (gregorian_jd >= start) {
        if (day > daysInMonth(year, month, true)) return null;
        return gregorian_jd;
    }
    const julian_jd = julianToJd(year, month, day);
    if (julian_jd >= start or day > daysInMonth(year, month, false)) return null;
    return julian_jd;
}

fn normalizeCivil(year: i64, month_arg: i64, day_arg: i64, start: i64) ?Civil {
    const month = if (month_arg < 0) month_arg + 13 else month_arg;
    if (month < 1 or month > 12) return null;
    if (day_arg > 0) return .{ .year = year, .month = month, .day = day_arg };
    if (day_arg == 0) return null;

    // Negative days count backward through valid dates, so skipped reform
    // dates do not consume positions.
    var remaining = -day_arg;
    var candidate: i64 = 31;
    while (candidate >= 1) : (candidate -= 1) {
        if (civilToJd(year, month, candidate, start) != null) {
            remaining -= 1;
            if (remaining == 0) return .{ .year = year, .month = month, .day = candidate };
        }
    }
    return null;
}

fn dateCivil(date: *value.DateObject) Civil {
    const jd = date.chronological_day.toInteger();
    const start = date.calendar_start.toInteger();
    return if (jd >= start) jdToGregorian(jd) else jdToJulian(jd);
}

fn dateIntegerArg(vm: *VM, arg: Value) VMError!i64 {
    return arg.coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "can't convert to Integer (to_int gives non-Integer)",
        "bignum too big to convert into `long'",
    );
}

fn builtinDateCivil(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 4);
    const year = if (args.len >= 1) try dateIntegerArg(vm, args[0]) else -4712;
    const month_arg = if (args.len >= 2) try dateIntegerArg(vm, args[1]) else 1;
    const day_arg = if (args.len >= 3) try dateIntegerArg(vm, args[2]) else 1;
    const start = if (args.len >= 4) try dateIntegerArg(vm, args[3]) else 2_299_161;
    const civil = normalizeCivil(year, month_arg, day_arg, start) orelse
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid date", .{});
    const jd = civilToJd(civil.year, civil.month, civil.day, start) orelse
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid date", .{});
    const zero = try vm.newRational(0, 1);
    return vm.newDate(receiver.toClassObject(), Value.integer(jd), zero, zero, Value.integer(start), .date);
}

fn builtinDateFromJd(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 2);
    const jd = if (args.len >= 1) try dateIntegerArg(vm, args[0]) else 0;
    const start = if (args.len == 2) try dateIntegerArg(vm, args[1]) else 2_299_161;
    const zero = try vm.newRational(0, 1);
    return vm.newDate(receiver.toClassObject(), Value.integer(jd), zero, zero, Value.integer(start), .date);
}

fn builtinDateValidDate(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 3, 4);
    for (args) |arg| {
        if (!arg.isInteger() and !arg.isBigInteger()) return Value.boolean(false);
    }
    const year = try dateIntegerArg(vm, args[0]);
    const month = try dateIntegerArg(vm, args[1]);
    const day = try dateIntegerArg(vm, args[2]);
    const start = if (args.len == 4) try dateIntegerArg(vm, args[3]) else 2_299_161;
    const civil = normalizeCivil(year, month, day, start) orelse return Value.boolean(false);
    return Value.boolean(civilToJd(civil.year, civil.month, civil.day, start) != null);
}

fn builtinDateValidJd(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    const candidate = args[0];
    return Value.boolean(candidate.isInteger() or candidate.isBigInteger() or candidate.isFloat() or candidate.isRational());
}

fn builtinDateGregorianLeap(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return Value.boolean(gregorianLeap(try dateIntegerArg(vm, args[0])));
}

fn builtinDateJulianLeap(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return Value.boolean(julianLeap(try dateIntegerArg(vm, args[0])));
}

fn builtinDateYear(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.integer(dateCivil(receiver.toDateObject()).year);
}

fn builtinDateMonth(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.integer(dateCivil(receiver.toDateObject()).month);
}

fn builtinDateDay(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.integer(dateCivil(receiver.toDateObject()).day);
}

fn builtinDateJd(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return receiver.toDateObject().chronological_day;
}

fn builtinDateAjd(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const jd = receiver.toDateObject().chronological_day.toInteger();
    return vm.newRational(jd * 2 - 1, 2);
}

fn builtinDateMjd(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.integer(receiver.toDateObject().chronological_day.toInteger() - 2_400_001);
}

fn builtinDateLd(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.integer(receiver.toDateObject().chronological_day.toInteger() - 2_299_160);
}

fn builtinDateDayFraction(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return receiver.toDateObject().sub_day_fraction;
}

fn builtinDateYday(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const date = receiver.toDateObject();
    const civil = dateCivil(date);
    const first_jd = civilToJd(civil.year, 1, 1, date.calendar_start.toInteger()).?;
    return Value.integer(date.chronological_day.toInteger() - first_jd + 1);
}

fn builtinDateWday(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.integer(@mod(receiver.toDateObject().chronological_day.toInteger() + 1, 7));
}

const Commercial = struct { year: i64, week: i64, day: i64 };

fn commercialDate(date: *value.DateObject) Commercial {
    const jd = date.chronological_day.toInteger();
    const day = @mod(jd, 7) + 1;
    const thursday_jd = jd + (4 - day);
    const thursday = dateCivilForJd(thursday_jd, date.calendar_start.toInteger());
    const jan4 = civilToJd(thursday.year, 1, 4, date.calendar_start.toInteger()).?;
    const week1_monday = jan4 - @mod(jan4, 7);
    return .{ .year = thursday.year, .week = @divFloor(jd - week1_monday, 7) + 1, .day = day };
}

fn dateCivilForJd(jd: i64, start: i64) Civil {
    return if (jd >= start) jdToGregorian(jd) else jdToJulian(jd);
}

fn builtinDateCwyear(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.integer(commercialDate(receiver.toDateObject()).year);
}

fn builtinDateCweek(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.integer(commercialDate(receiver.toDateObject()).week);
}

fn builtinDateCwday(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.integer(commercialDate(receiver.toDateObject()).day);
}

fn builtinDateJulian(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const date = receiver.toDateObject();
    return Value.boolean(date.chronological_day.toInteger() < date.calendar_start.toInteger());
}

fn builtinDateGregorian(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const result = try builtinDateJulian(vm, receiver, args, null);
    return Value.boolean(!result.toBool());
}

fn builtinDateSucc(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const date = receiver.toDateObject();
    return vm.newDate(
        date.object.class.?,
        Value.integer(date.chronological_day.toInteger() + 1),
        date.sub_day_fraction,
        date.utc_offset,
        date.calendar_start,
        date.kind,
    );
}

fn dateWithDay(vm: *VM, source: *value.DateObject, jd: i64) VMError!Value {
    return vm.newDate(source.object.class.?, Value.integer(jd), source.sub_day_fraction, source.utc_offset, source.calendar_start, source.kind);
}

fn numericDayCount(vm: *VM, arg: Value) VMError!i64 {
    if (!arg.isInteger() and !arg.isBigInteger()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "expected numeric", .{});
    }
    return dateIntegerArg(vm, arg);
}

fn builtinDateAdd(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const amount = try numericDayCount(vm, args[0]);
    const date = receiver.toDateObject();
    return dateWithDay(vm, date, date.chronological_day.toInteger() + amount);
}

fn builtinDateSubtract(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const date = receiver.toDateObject();
    if (args[0].isDate()) {
        return Value.integer(date.chronological_day.toInteger() - args[0].toDateObject().chronological_day.toInteger());
    }
    const amount = try numericDayCount(vm, args[0]);
    return dateWithDay(vm, date, date.chronological_day.toInteger() - amount);
}

fn shiftMonths(vm: *VM, receiver: Value, amount: i64) VMError!Value {
    const date = receiver.toDateObject();
    const civil = dateCivil(date);
    const month_index = civil.year * 12 + civil.month - 1 + amount;
    const year = @divFloor(month_index, 12);
    const month = @mod(month_index, 12) + 1;
    var day = civil.day;
    const start = date.calendar_start.toInteger();
    while (day > 0) : (day -= 1) {
        if (civilToJd(year, month, day, start)) |jd| return dateWithDay(vm, date, jd);
    }
    unreachable;
}

fn builtinDateAddMonths(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return shiftMonths(vm, receiver, try numericDayCount(vm, args[0]));
}

fn builtinDateSubtractMonths(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return shiftMonths(vm, receiver, -(try numericDayCount(vm, args[0])));
}

fn builtinDateNextDay(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const amount = if (args.len == 1) try numericDayCount(vm, args[0]) else 1;
    const date = receiver.toDateObject();
    return dateWithDay(vm, date, date.chronological_day.toInteger() + amount);
}

fn builtinDatePrevDay(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const amount = if (args.len == 1) try numericDayCount(vm, args[0]) else 1;
    const date = receiver.toDateObject();
    return dateWithDay(vm, date, date.chronological_day.toInteger() - amount);
}

fn builtinDateCompare(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const lhs = receiver.toDateObject().chronological_day;
    const rhs = if (args[0].isDate()) args[0].toDateObject().chronological_day else args[0];
    if (rhs.isInteger() or rhs.isBigInteger()) {
        return switch (try vm.compareIntegerValues(lhs, rhs)) {
            .lt => Value.integer(-1),
            .eq => Value.integer(0),
            .gt => Value.integer(1),
        };
    }
    if (rhs.isFloat() or rhs.isRational()) {
        return vm.callMethodByName(lhs, "<=>", args[0..1], null);
    }
    return Value.nil();
}

fn builtinDateEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const comparison = try builtinDateCompare(vm, receiver, args, null);
    return Value.boolean(comparison.isInteger() and comparison.toInteger() == 0);
}

pub fn builtinDateAllocate(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return allocateDate(vm, receiver.toClassObject(), .date);
}

fn builtinDateTimeAllocate(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return allocateDate(vm, receiver.toClassObject(), .datetime);
}

fn allocateDate(vm: *VM, class: *value.ClassObject, kind: value.DateKind) VMError!Value {
    const zero = try vm.newRational(0, 1);
    return vm.newDate(class, Value.integer(0), zero, zero, Value.integer(2_299_161), kind);
}

fn builtinDateInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const date = receiver.toDateObject();
    const class_name = if (date.kind == .datetime) "DateTime" else "Date";
    const text = std.fmt.allocPrint(vm.gc_allocator, "#<{s}: day={d}>", .{ class_name, date.chronological_day.toInteger() }) catch return error.Fatal;
    return vm.newString(text, false);
}

fn builtinDateEql(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return Value.boolean(receiver.eql(args[0]));
}

fn builtinDateHash(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.integer(@bitCast(receiver.hash()));
}
