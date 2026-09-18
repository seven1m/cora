const std = @import("std");
const strftime_fmt = @import("strftime.zig");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const Block = vm_mod.Block;
const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Value = value.Value;

// These sentinels are used only for calendar calculations. Public Date start
// values use the MRI-compatible +/-Infinity Float values below.
const GREGORIAN_START: i64 = std.math.minInt(i64);
const JULIAN_START: i64 = std.math.maxInt(i64);
const DEFAULT_CALENDAR_START: i64 = 2_299_161;

const CalendarStart = struct {
    jd: i64,
    value: Value,
};

pub fn register(vm: *VM) !void {
    const date_name = try vm.intern("Date");
    if (vm.object_class.module.constants.contains(date_name)) return;

    const date_value = try vm.newClass(date_name, vm.object_class);
    const date_class = date_value.toClassObject();
    date_class.builtin_alloc_func = &builtinDateAllocate;
    try vm.setConstant(&vm.object_class.module, date_name, date_value);

    try date_class.module.constants.put(try vm.intern("ITALY"), .{ .value = Value.integer(2_299_161) });
    try date_class.module.constants.put(try vm.intern("ENGLAND"), .{ .value = Value.integer(2_361_222) });
    try date_class.module.constants.put(try vm.intern("GREGORIAN"), .{ .value = try vm.newFloat(-std.math.inf(f64)) });
    try date_class.module.constants.put(try vm.intern("JULIAN"), .{ .value = try vm.newFloat(std.math.inf(f64)) });

    const datetime_name = try vm.intern("DateTime");
    const datetime_value = try vm.newClass(datetime_name, date_class);
    const datetime_class = datetime_value.toClassObject();
    datetime_class.builtin_alloc_func = &builtinDateTimeAllocate;
    try vm.setConstant(&vm.object_class.module, datetime_name, datetime_value);

    const datetime_singleton = try vm.getOrCreateSingletonClass(datetime_value);
    const datetime_civil_entry = value.MethodEntry.builtin(&builtinDateTimeCivil, .{ .variadic = 0 });
    try datetime_singleton.module.methods.put(try vm.intern("new"), datetime_civil_entry);
    try datetime_singleton.module.methods.put(try vm.intern("civil"), datetime_civil_entry);
    try datetime_singleton.module.methods.put(try vm.intern("jd"), value.MethodEntry.builtin(&builtinDateTimeJd, .{ .variadic = 0 }));
    try datetime_singleton.module.methods.put(try vm.intern("now"), value.MethodEntry.builtin(&builtinDateTimeNow, .{ .exact = 0 }));

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
    try date_class.module.methods.put(try vm.intern("strftime"), value.MethodEntry.builtin(&builtinDateStrftime, .{ .exact = 1 }));
    try date_class.module.methods.put(try vm.intern("start"), value.MethodEntry.builtin(&builtinDateStart, .{ .exact = 0 }));
    try date_class.module.methods.put(try vm.intern("yday"), value.MethodEntry.builtin(&builtinDateYday, .{ .exact = 0 }));
    try date_class.module.methods.put(try vm.intern("wday"), value.MethodEntry.builtin(&builtinDateWday, .{ .exact = 0 }));
    try date_class.module.methods.put(try vm.intern("cwyear"), value.MethodEntry.builtin(&builtinDateCwyear, .{ .exact = 0 }));
    try date_class.module.methods.put(try vm.intern("cweek"), value.MethodEntry.builtin(&builtinDateCweek, .{ .exact = 0 }));
    try date_class.module.methods.put(try vm.intern("cwday"), value.MethodEntry.builtin(&builtinDateCwday, .{ .exact = 0 }));
    try date_class.module.methods.put(try vm.intern("julian?"), value.MethodEntry.builtin(&builtinDateJulian, .{ .exact = 0 }));
    try date_class.module.methods.put(try vm.intern("gregorian?"), value.MethodEntry.builtin(&builtinDateGregorian, .{ .exact = 0 }));
    try date_class.module.methods.put(try vm.intern("gregorian"), value.MethodEntry.builtin(&builtinDateGregorianConversion, .{ .exact = 0 }));
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

    try datetime_class.module.methods.put(try vm.intern("hour"), value.MethodEntry.builtin(&builtinDateTimeHour, .{ .exact = 0 }));
    const minute_entry = value.MethodEntry.builtin(&builtinDateTimeMinute, .{ .exact = 0 });
    try datetime_class.module.methods.put(try vm.intern("minute"), minute_entry);
    try datetime_class.module.methods.put(try vm.intern("min"), minute_entry);
    const second_entry = value.MethodEntry.builtin(&builtinDateTimeSecond, .{ .exact = 0 });
    try datetime_class.module.methods.put(try vm.intern("second"), second_entry);
    try datetime_class.module.methods.put(try vm.intern("sec"), second_entry);
    const second_fraction_entry = value.MethodEntry.builtin(&builtinDateTimeSecondFraction, .{ .exact = 0 });
    try datetime_class.module.methods.put(try vm.intern("second_fraction"), second_fraction_entry);
    try datetime_class.module.methods.put(try vm.intern("sec_fraction"), second_fraction_entry);
    try datetime_class.module.methods.put(try vm.intern("offset"), value.MethodEntry.builtin(&builtinDateTimeOffset, .{ .exact = 0 }));
    try datetime_class.module.methods.put(try vm.intern("start"), value.MethodEntry.builtin(&builtinDateStart, .{ .exact = 0 }));
    try datetime_class.module.methods.put(try vm.intern("+"), value.MethodEntry.builtin(&builtinDateTimeAdd, .{ .exact = 1 }));
    try datetime_class.module.methods.put(try vm.intern("-"), value.MethodEntry.builtin(&builtinDateTimeSubtract, .{ .exact = 1 }));
    try datetime_class.module.methods.put(try vm.intern("new_offset"), value.MethodEntry.builtin(&builtinDateTimeNewOffset, .{ .variadic = 0 }));
    try datetime_class.module.methods.put(try vm.intern("to_date"), value.MethodEntry.builtin(&builtinDateTimeToDate, .{ .exact = 0 }));
    try datetime_class.module.methods.put(try vm.intern("to_datetime"), value.MethodEntry.builtin(&builtinDateTimeToDateTime, .{ .exact = 0 }));
    try datetime_class.module.methods.put(try vm.intern("to_time"), value.MethodEntry.builtin(&builtinDateTimeToTime, .{ .exact = 0 }));

    try vm.time_class.module.methods.put(try vm.intern("to_datetime"), value.MethodEntry.builtin(&builtinTimeToDateTime, .{ .exact = 0 }));
    try vm.time_class.module.methods.put(try vm.intern("to_date"), value.MethodEntry.builtin(&builtinTimeToDate, .{ .exact = 0 }));
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
    const start = calendarStartInteger(date.calendar_start);
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

fn calendarStartInteger(start: Value) i64 {
    if (start.isFloat()) {
        const number = start.toFloatObject().val;
        if (std.math.isInf(number)) return if (number < 0) GREGORIAN_START else JULIAN_START;
    }
    return start.toInteger();
}

fn calendarStartArg(vm: *VM, arg: Value) VMError!CalendarStart {
    if (arg.isFloat() and std.math.isInf(arg.toFloatObject().val)) {
        return .{
            .jd = calendarStartInteger(arg),
            .value = arg,
        };
    }
    const jd = try dateIntegerArg(vm, arg);
    return .{ .jd = jd, .value = Value.integer(jd) };
}

fn defaultCalendarStart() CalendarStart {
    return .{ .jd = DEFAULT_CALENDAR_START, .value = Value.integer(DEFAULT_CALENDAR_START) };
}

fn numberToF64(value_arg: Value) ?f64 {
    if (value_arg.isInteger()) return @floatFromInt(value_arg.toInteger());
    if (value_arg.isBigInteger()) return value_arg.integerToF64();
    if (value_arg.isFloat()) return value_arg.toFloatObject().val;
    if (value_arg.isRational()) {
        const rational = value_arg.toRationalObject();
        return rational.numerator.integerToF64() / rational.denominator.integerToF64();
    }
    return null;
}

fn parseOffsetString(bytes: []const u8) ?i64 {
    if (bytes.len != 6 or (bytes[0] != '+' and bytes[0] != '-') or bytes[3] != ':') return null;
    if (!std.ascii.isDigit(bytes[1]) or !std.ascii.isDigit(bytes[2]) or !std.ascii.isDigit(bytes[4]) or !std.ascii.isDigit(bytes[5])) return null;
    const hours = @as(i64, bytes[1] - '0') * 10 + (bytes[2] - '0');
    const minutes = @as(i64, bytes[4] - '0') * 10 + (bytes[5] - '0');
    if (hours > 23 or minutes > 59) return null;
    const seconds = hours * 3600 + minutes * 60;
    return if (bytes[0] == '-') -seconds else seconds;
}

fn normalizeOffset(vm: *VM, offset_arg: Value) VMError!Value {
    if (offset_arg.isString()) {
        const seconds = parseOffsetString(offset_arg.toStringObject().str) orelse return vm.raiseExceptionFmt(vm.argument_error_class, "invalid offset", .{});
        return vm.newRational(seconds, 86_400);
    }
    if (numberToF64(offset_arg) == null) return vm.raiseExceptionFmt(vm.argument_error_class, "invalid offset", .{});
    if (offset_arg.isFloat()) return vm.callMethodByName(offset_arg, "to_r", &.{}, null);
    return offset_arg;
}

fn exactNumeric(vm: *VM, number: Value) VMError!Value {
    return if (number.isFloat()) vm.callMethodByName(number, "to_r", &.{}, null) else number;
}

fn callNumeric(vm: *VM, receiver: Value, method: []const u8, argument: Value) VMError!Value {
    var normalized_receiver = receiver;
    var normalized_argument = argument;
    if ((receiver.isFloat() and argument.isRational()) or (receiver.isRational() and argument.isFloat())) {
        normalized_receiver = try vm.newFloat(numberToF64(receiver).?);
        normalized_argument = try vm.newFloat(numberToF64(argument).?);
    }
    var args = [_]Value{normalized_argument};
    return vm.callMethodByName(normalized_receiver, method, &args, null);
}

fn dateTimeFraction(vm: *VM, hour: i64, minute: i64, second: Value) VMError!Value {
    const whole_seconds = hour * 3600 + minute * 60;
    if (second.isInteger()) return vm.newRational(whole_seconds + second.toInteger(), 86_400);
    if (second.isRational()) {
        const rational = second.toRationalObject();
        const whole = try vm.mulIntegerValues(Value.integer(whole_seconds), rational.denominator);
        const numerator = try vm.addIntegerValues(whole, rational.numerator);
        const denominator = try vm.mulIntegerValues(rational.denominator, Value.integer(86_400));
        return vm.newRationalValues(numerator, denominator);
    }
    if (second.isFloat()) return vm.newFloat((@as(f64, @floatFromInt(whole_seconds)) + second.toFloatObject().val) / 86_400.0);
    return vm.raiseExceptionFmt(vm.type_error_class, "expected numeric", .{});
}

fn builtinDateTimeCivil(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 8);
    const integer_field_count = @min(args.len, 5);
    for (args[0..integer_field_count]) |arg| {
        if (!arg.isInteger() and !arg.isBigInteger()) return vm.raiseExceptionFmt(vm.argument_error_class, "invalid date", .{});
    }
    const year = if (args.len >= 1) try dateIntegerArg(vm, args[0]) else -4712;
    const month_arg = if (args.len >= 2) try dateIntegerArg(vm, args[1]) else 1;
    const day_arg = if (args.len >= 3) try dateIntegerArg(vm, args[2]) else 1;
    var hour = if (args.len >= 4) try dateIntegerArg(vm, args[3]) else 0;
    var minute = if (args.len >= 5) try dateIntegerArg(vm, args[4]) else 0;
    const second = if (args.len >= 6) args[5] else Value.integer(0);
    const second_number = numberToF64(second) orelse return vm.raiseExceptionFmt(vm.argument_error_class, "invalid date", .{});
    const offset = if (args.len >= 7) try normalizeOffset(vm, args[6]) else try vm.newRational(0, 1);
    const offset_number = numberToF64(offset) orelse return vm.raiseExceptionFmt(vm.argument_error_class, "invalid offset", .{});
    const start_info = if (args.len >= 8) try calendarStartArg(vm, args[7]) else defaultCalendarStart();
    const start = start_info.jd;

    if (hour < -24 or hour > 24 or minute < -60 or minute >= 60 or second_number <= -60 or second_number >= 60 or offset_number <= -1 or offset_number >= 1) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid date", .{});
    }
    var day_adjust: i64 = 0;
    if (hour == 24) {
        hour = 0;
        day_adjust = 1;
    } else if (hour < 0) hour += 24;
    if (minute < 0) minute += 60;
    var normalized_second = if (second_number < 0) blk: {
        minute -= 1;
        var add_args = [_]Value{Value.integer(60)};
        break :blk try vm.callMethodByName(second, "+", &add_args, null);
    } else second;
    normalized_second = try exactNumeric(vm, normalized_second);
    if (minute < 0) {
        minute += 60;
        hour -= 1;
    }
    if (hour < 0) {
        hour += 24;
        day_adjust -= 1;
    }

    const civil = normalizeCivil(year, month_arg, day_arg, start) orelse return vm.raiseExceptionFmt(vm.argument_error_class, "invalid date", .{});
    const jd = (civilToJd(civil.year, civil.month, civil.day, start) orelse return vm.raiseExceptionFmt(vm.argument_error_class, "invalid date", .{})) + day_adjust;
    const fraction = try dateTimeFraction(vm, hour, minute, normalized_second);
    return vm.newDate(receiver.toClassObject(), Value.integer(jd), fraction, offset, start_info.value, .datetime);
}

fn dateTimeAbsoluteDay(vm: *VM, date: *value.DateObject) VMError!Value {
    const with_fraction = try callNumeric(vm, date.chronological_day, "+", date.sub_day_fraction);
    return callNumeric(vm, with_fraction, "-", date.utc_offset);
}

fn dateTimeFromAbsoluteDay(vm: *VM, class: *value.ClassObject, absolute_day: Value, offset: Value, start: Value) VMError!Value {
    const local_day = try callNumeric(vm, absolute_day, "+", offset);
    const floor = try vm.callMethodByName(local_day, "floor", &.{}, null);
    const fraction = try callNumeric(vm, local_day, "-", floor);
    return vm.newDate(class, floor, fraction, offset, start, .datetime);
}

fn builtinDateTimeAdd(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (numberToF64(args[0]) == null) return vm.raiseExceptionFmt(vm.type_error_class, "expected numeric", .{});
    const date = receiver.toDateObject();
    const absolute = try dateTimeAbsoluteDay(vm, date);
    return dateTimeFromAbsoluteDay(vm, date.object.class.?, try callNumeric(vm, absolute, "+", try exactNumeric(vm, args[0])), date.utc_offset, date.calendar_start);
}

fn builtinDateTimeSubtract(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const date = receiver.toDateObject();
    const absolute = try dateTimeAbsoluteDay(vm, date);
    if (args[0].isDate()) return callNumeric(vm, absolute, "-", try dateTimeAbsoluteDay(vm, args[0].toDateObject()));
    if (numberToF64(args[0]) == null) return vm.raiseExceptionFmt(vm.type_error_class, "expected numeric", .{});
    return dateTimeFromAbsoluteDay(vm, date.object.class.?, try callNumeric(vm, absolute, "-", try exactNumeric(vm, args[0])), date.utc_offset, date.calendar_start);
}

fn builtinDateTimeNewOffset(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const offset = if (args.len == 1) try normalizeOffset(vm, args[0]) else try vm.newRational(0, 1);
    const date = receiver.toDateObject();
    return dateTimeFromAbsoluteDay(vm, date.object.class.?, try dateTimeAbsoluteDay(vm, date), offset, date.calendar_start);
}

fn builtinDateTimeToDate(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const date_class_value = (try vm.resolveConstantPath("Date")) orelse return error.Fatal;
    const date = receiver.toDateObject();
    const zero = try vm.newRational(0, 1);
    return vm.newDate(date_class_value.toClassObject(), date.chronological_day, zero, zero, date.calendar_start, .date);
}

fn builtinDateTimeToDateTime(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return receiver;
}

fn offsetNanoseconds(offset: Value) i64 {
    return @intFromFloat(numberToF64(offset).? * 86_400.0 * 1_000_000_000.0);
}

fn builtinDateTimeToTime(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const date = receiver.toDateObject();
    var epoch_days = try callNumeric(vm, try dateTimeAbsoluteDay(vm, date), "-", Value.integer(2_440_588));
    epoch_days = try callNumeric(vm, epoch_days, "*", Value.integer(86_400_000_000_000));
    if (epoch_days.isFloat()) epoch_days = try vm.callMethodByName(epoch_days, "to_r", &.{}, null);
    return vm.newTimeWithOffset(vm.time_class, epoch_days, offsetNanoseconds(date.utc_offset));
}

fn builtinTimeToDateTime(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const time = receiver.toTimeObject();
    var local_nanos = time.timew;
    if (time.utc_offset_nanos != 0) local_nanos = try callNumeric(vm, local_nanos, "+", Value.integer(time.utc_offset_nanos));
    const nanos_per_day = Value.integer(86_400_000_000_000);
    const day_value = if (local_nanos.isInteger() or local_nanos.isBigInteger())
        try vm.newRationalValues(local_nanos, nanos_per_day)
    else if (local_nanos.isRational()) blk: {
        const rational = local_nanos.toRationalObject();
        break :blk try vm.newRationalValues(rational.numerator, try vm.mulIntegerValues(rational.denominator, nanos_per_day));
    } else try callNumeric(vm, local_nanos, "/", nanos_per_day);
    const days = try vm.callMethodByName(day_value, "floor", &.{}, null);
    const fraction = try callNumeric(vm, day_value, "-", days);
    const jd = try vm.addIntegerValues(days, Value.integer(2_440_588));
    const offset = try vm.newRational(time.utc_offset_nanos, 86_400_000_000_000);
    const datetime_value = (try vm.resolveConstantPath("DateTime")) orelse return error.Fatal;
    return vm.newDate(datetime_value.toClassObject(), jd, fraction, offset, Value.integer(2_299_161), .datetime);
}

fn builtinTimeToDate(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const datetime = try builtinTimeToDateTime(vm, receiver, &.{}, null);
    return builtinDateTimeToDate(vm, datetime, &.{}, null);
}

fn builtinDateTimeNow(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const time_value = try vm.callMethodByName(Value.fromObject(&vm.time_class.module.object), "now", &.{}, null);
    const datetime = try builtinTimeToDateTime(vm, time_value, &.{}, null);
    datetime.toDateObject().object.class = receiver.toClassObject();
    return datetime;
}

fn builtinDateTimeJd(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 6);
    const jd = if (args.len >= 1) try dateIntegerArg(vm, args[0]) else 0;
    var civil_args: [8]Value = .{ Value.integer(-4712), Value.integer(1), Value.integer(1), Value.integer(0), Value.integer(0), Value.integer(0), try vm.newRational(0, 1), Value.integer(DEFAULT_CALENDAR_START) };
    const start_info = if (args.len >= 6) try calendarStartArg(vm, args[5]) else defaultCalendarStart();
    const start = start_info.jd;
    const civil = dateCivilForJd(jd, start);
    civil_args[0] = Value.integer(civil.year);
    civil_args[1] = Value.integer(civil.month);
    civil_args[2] = Value.integer(civil.day);
    if (args.len >= 2) civil_args[3] = args[1];
    if (args.len >= 3) civil_args[4] = args[2];
    if (args.len >= 4) civil_args[5] = args[3];
    if (args.len >= 5) civil_args[6] = args[4];
    civil_args[7] = start_info.value;
    return builtinDateTimeCivil(vm, receiver, &civil_args, block);
}

fn builtinDateCivil(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 4);
    const year = if (args.len >= 1) try dateIntegerArg(vm, args[0]) else -4712;
    const month_arg = if (args.len >= 2) try dateIntegerArg(vm, args[1]) else 1;
    const day_arg = if (args.len >= 3) try dateIntegerArg(vm, args[2]) else 1;
    const start_info = if (args.len >= 4) try calendarStartArg(vm, args[3]) else defaultCalendarStart();
    const start = start_info.jd;
    const civil = normalizeCivil(year, month_arg, day_arg, start) orelse
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid date", .{});
    const jd = civilToJd(civil.year, civil.month, civil.day, start) orelse
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid date", .{});
    const zero = try vm.newRational(0, 1);
    return vm.newDate(receiver.toClassObject(), Value.integer(jd), zero, zero, start_info.value, .date);
}

fn builtinDateFromJd(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 2);
    const jd = if (args.len >= 1) try dateIntegerArg(vm, args[0]) else 0;
    const start_info = if (args.len == 2) try calendarStartArg(vm, args[1]) else defaultCalendarStart();
    const zero = try vm.newRational(0, 1);
    return vm.newDate(receiver.toClassObject(), Value.integer(jd), zero, zero, start_info.value, .date);
}

fn builtinDateValidDate(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 3, 4);
    for (args[0..3]) |arg| {
        if (!arg.isInteger() and !arg.isBigInteger()) return Value.boolean(false);
    }
    const year = try dateIntegerArg(vm, args[0]);
    const month = try dateIntegerArg(vm, args[1]);
    const day = try dateIntegerArg(vm, args[2]);
    const start = (if (args.len == 4) calendarStartArg(vm, args[3]) else defaultCalendarStart()) catch return Value.boolean(false);
    const civil = normalizeCivil(year, month, day, start.jd) orelse return Value.boolean(false);
    return Value.boolean(civilToJd(civil.year, civil.month, civil.day, start.jd) != null);
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

fn dateTimeSeconds(date: *value.DateObject) f64 {
    return numberToF64(date.sub_day_fraction).? * 86_400.0;
}

fn dateTimeWholeSeconds(vm: *VM, date: *value.DateObject) VMError!i64 {
    if (date.sub_day_fraction.isRational()) {
        const rational = date.sub_day_fraction.toRationalObject();
        const scaled = try vm.mulIntegerValues(rational.numerator, Value.integer(86_400));
        return (try vm.divFloorIntegerValues(scaled, rational.denominator)).integerToI64(vm, "date out of range");
    }
    return @intFromFloat(@floor(dateTimeSeconds(date)));
}

fn builtinDateTimeHour(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.integer(@divFloor(try dateTimeWholeSeconds(vm, receiver.toDateObject()), 3600));
}

fn builtinDateTimeMinute(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.integer(@divFloor(@mod(try dateTimeWholeSeconds(vm, receiver.toDateObject()), 3600), 60));
}

fn builtinDateTimeSecond(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.integer(@mod(try dateTimeWholeSeconds(vm, receiver.toDateObject()), 60));
}

fn builtinDateTimeSecondFraction(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const date = receiver.toDateObject();
    if (date.sub_day_fraction.isRational()) {
        const rational = date.sub_day_fraction.toRationalObject();
        const scaled = try vm.mulIntegerValues(rational.numerator, Value.integer(86_400));
        const whole = try vm.divFloorIntegerValues(scaled, rational.denominator);
        const consumed = try vm.mulIntegerValues(whole, rational.denominator);
        const remainder = try vm.subIntegerValues(scaled, consumed);
        return vm.newRationalValues(remainder, rational.denominator);
    }
    const seconds = dateTimeSeconds(date);
    return vm.newFloat(seconds - @floor(seconds));
}

fn builtinDateStrftime(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const format = try args[0].coerceToStringValue(vm, "no implicit conversion into String");
    const date = receiver.toDateObject();
    const civil = dateCivil(date);

    var hour: u8 = 0;
    var minute: u8 = 0;
    var second: u8 = 0;
    var nanosecond: u32 = 0;
    var utc_offset_nanos: i64 = 0;
    if (date.kind == .datetime) {
        const whole_seconds = try dateTimeWholeSeconds(vm, date);
        hour = @intCast(@divFloor(whole_seconds, 3600));
        minute = @intCast(@divFloor(@mod(whole_seconds, 3600), 60));
        second = @intCast(@mod(whole_seconds, 60));
        const fraction = try builtinDateTimeSecondFraction(vm, receiver, &.{}, null);
        nanosecond = @intFromFloat(@floor(numberToF64(fraction).? * 1_000_000_000.0));
        utc_offset_nanos = offsetNanoseconds(date.utc_offset);
    }

    const first_jd = civilToJd(civil.year, 1, 1, calendarStartInteger(date.calendar_start)).?;
    return strftime_fmt.build(vm, .{
        .year = Value.integer(civil.year),
        .month = @intCast(civil.month),
        .day = @intCast(civil.day),
        .hour = hour,
        .minute = minute,
        .second = second,
        .nanosecond = nanosecond,
        .weekday = @intCast(@mod(date.chronological_day.toInteger() + 1, 7)),
        .year_day = @intCast(date.chronological_day.toInteger() - first_jd + 1),
    }, .{
        .utc_offset_nanos = utc_offset_nanos,
        .is_utc = false,
        .name_style = .offset,
    }, format.toStringObject().str);
}

fn builtinDateTimeOffset(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return receiver.toDateObject().utc_offset;
}

fn builtinDateStart(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return receiver.toDateObject().calendar_start;
}

fn builtinDateYday(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const date = receiver.toDateObject();
    const civil = dateCivil(date);
    const first_jd = civilToJd(civil.year, 1, 1, calendarStartInteger(date.calendar_start)).?;
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
    const start = calendarStartInteger(date.calendar_start);
    const thursday = dateCivilForJd(thursday_jd, start);
    const jan4 = civilToJd(thursday.year, 1, 4, start).?;
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
    return Value.boolean(date.chronological_day.toInteger() < calendarStartInteger(date.calendar_start));
}

fn builtinDateGregorian(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const result = try builtinDateJulian(vm, receiver, args, null);
    return Value.boolean(!result.toBool());
}

fn builtinDateGregorianConversion(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const date = receiver.toDateObject();
    return vm.newDate(
        date.object.class.?,
        date.chronological_day,
        date.sub_day_fraction,
        date.utc_offset,
        try vm.newFloat(-std.math.inf(f64)),
        date.kind,
    );
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
    const start = calendarStartInteger(date.calendar_start);
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
