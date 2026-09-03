const std = @import("std");
const rational = @import("rational.zig");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

extern "c" fn clock_gettime(clk_id: std.posix.CLOCK, tp: *std.posix.timespec) c_int;
extern "c" fn tzset() void;
extern "c" fn strftime(ptr: [*]u8, maxsize: usize, format: [*:0]const u8, tm: *const CStructTm) usize;

// localtime_r(3) gives us struct tm with tm_gmtoff (POSIX extension).
const c_time_t = i64;
const CStructTm = extern struct {
    tm_sec: c_int,
    tm_min: c_int,
    tm_hour: c_int,
    tm_mday: c_int,
    tm_mon: c_int,
    tm_year: c_int,
    tm_wday: c_int,
    tm_yday: c_int,
    tm_isdst: c_int,
    tm_gmtoff: c_long,
    tm_zone: ?[*:0]const u8,
};
extern "c" fn localtime_r(timep: *const c_time_t, result: *CStructTm) ?*CStructTm;

const nanos_per_second: i64 = 1_000_000_000;
const seconds_per_minute: i64 = 60;
const minutes_per_hour: i64 = 60;
const hours_per_day: i64 = 24;
const seconds_per_hour: i64 = seconds_per_minute * minutes_per_hour;
const seconds_per_day: i64 = seconds_per_hour * hours_per_day;

const max_utc_offset_seconds: i64 = 86400 - 1; // +/-86399

const CivilDate = struct {
    year: Value,
    month: u8,
    day: u8,
};

const TimeParts = struct {
    year: Value,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
    nanosecond: u32,
    weekday: u8,
    year_day: u16,
};

pub fn register(vm: *VM) !void {
    const time_class_val = Value.fromObject(&vm.time_class.module.object);
    const time_singleton = try vm.getOrCreateSingletonClass(time_class_val);

    const new_sym = try vm.intern("new");
    try time_singleton.module.methods.put(new_sym, value.MethodEntry.builtin(&builtinTimeNew, .{ .variadic = 0 }));

    const now_sym = try vm.intern("now");
    try time_singleton.module.methods.put(now_sym, value.MethodEntry.builtin(&builtinTimeNow, .{ .variadic = 0 }));

    const utc_sym = try vm.intern("utc");
    try time_singleton.module.methods.put(utc_sym, value.MethodEntry.builtin(&builtinTimeUtc, .{ .variadic = 0 }));

    const gm_sym = try vm.intern("gm");
    try time_singleton.module.methods.put(gm_sym, value.MethodEntry.builtin(&builtinTimeUtc, .{ .variadic = 0 }));

    const local_sym = try vm.intern("local");
    try time_singleton.module.methods.put(local_sym, value.MethodEntry.builtin(&builtinTimeLocal, .{ .variadic = 0 }));

    const mktime_sym = try vm.intern("mktime");
    try time_singleton.module.methods.put(mktime_sym, value.MethodEntry.builtin(&builtinTimeLocal, .{ .variadic = 0 }));

    const at_sym = try vm.intern("at");
    try time_singleton.module.methods.put(at_sym, value.MethodEntry.builtin(&builtinTimeAt, .{ .variadic = 1 }));

    const load_sym = try vm.intern("_load");
    try time_singleton.module.methods.put(load_sym, value.MethodEntry.builtin(&builtinTimeLoad, .{ .exact = 1 }));

    const plus_sym = try vm.intern("+");
    try vm.time_class.module.methods.put(plus_sym, value.MethodEntry.builtin(&builtinTimePlus, .{ .exact = 1 }));

    const minus_sym = try vm.intern("-");
    try vm.time_class.module.methods.put(minus_sym, value.MethodEntry.builtin(&builtinTimeMinus, .{ .exact = 1 }));

    const compare_sym = try vm.intern("<=>");
    try vm.time_class.module.methods.put(compare_sym, value.MethodEntry.builtin(&builtinTimeCompare, .{ .exact = 1 }));

    try vm.time_class.module.methods.put(utc_sym, value.MethodEntry.builtin(&builtinTimeUtcInstance, .{ .exact = 0 }));

    const getutc_sym = try vm.intern("getutc");
    try vm.time_class.module.methods.put(getutc_sym, value.MethodEntry.builtin(&builtinTimeUtcInstance, .{ .exact = 0 }));

    const gmtime_sym = try vm.intern("gmtime");
    try vm.time_class.module.methods.put(gmtime_sym, value.MethodEntry.builtin(&builtinTimeUtcInstance, .{ .exact = 0 }));

    const utc_q_sym = try vm.intern("utc?");
    try vm.time_class.module.methods.put(utc_q_sym, value.MethodEntry.builtin(&builtinTimeUtcQ, .{ .exact = 0 }));

    const gmt_q_sym = try vm.intern("gmt?");
    try vm.time_class.module.methods.put(gmt_q_sym, value.MethodEntry.builtin(&builtinTimeUtcQ, .{ .exact = 0 }));

    const localtime_sym = try vm.intern("localtime");
    try vm.time_class.module.methods.put(localtime_sym, value.MethodEntry.builtin(&builtinTimeLocaltime, .{ .variadic = 0 }));

    const utc_offset_sym = try vm.intern("utc_offset");
    try vm.time_class.module.methods.put(utc_offset_sym, value.MethodEntry.builtin(&builtinTimeUtcOffset, .{ .exact = 0 }));

    const gmt_offset_sym = try vm.intern("gmt_offset");
    try vm.time_class.module.methods.put(gmt_offset_sym, value.MethodEntry.builtin(&builtinTimeUtcOffset, .{ .exact = 0 }));

    const gmtoff_sym = try vm.intern("gmtoff");
    try vm.time_class.module.methods.put(gmtoff_sym, value.MethodEntry.builtin(&builtinTimeUtcOffset, .{ .exact = 0 }));

    const year_sym = try vm.intern("year");
    try vm.time_class.module.methods.put(year_sym, value.MethodEntry.builtin(&builtinTimeYear, .{ .exact = 0 }));

    const month_sym = try vm.intern("month");
    try vm.time_class.module.methods.put(month_sym, value.MethodEntry.builtin(&builtinTimeMonth, .{ .exact = 0 }));

    const mon_sym = try vm.intern("mon");
    try vm.time_class.module.methods.put(mon_sym, value.MethodEntry.builtin(&builtinTimeMonth, .{ .exact = 0 }));

    const day_sym = try vm.intern("day");
    try vm.time_class.module.methods.put(day_sym, value.MethodEntry.builtin(&builtinTimeDay, .{ .exact = 0 }));

    const mday_sym = try vm.intern("mday");
    try vm.time_class.module.methods.put(mday_sym, value.MethodEntry.builtin(&builtinTimeDay, .{ .exact = 0 }));

    const hour_sym = try vm.intern("hour");
    try vm.time_class.module.methods.put(hour_sym, value.MethodEntry.builtin(&builtinTimeHour, .{ .exact = 0 }));

    const min_sym = try vm.intern("min");
    try vm.time_class.module.methods.put(min_sym, value.MethodEntry.builtin(&builtinTimeMin, .{ .exact = 0 }));

    const sec_sym = try vm.intern("sec");
    try vm.time_class.module.methods.put(sec_sym, value.MethodEntry.builtin(&builtinTimeSec, .{ .exact = 0 }));

    const to_i_sym = try vm.intern("to_i");
    try vm.time_class.module.methods.put(to_i_sym, value.MethodEntry.builtin(&builtinTimeToI, .{ .exact = 0 }));

    const tv_sec_sym = try vm.intern("tv_sec");
    try vm.time_class.module.methods.put(tv_sec_sym, value.MethodEntry.builtin(&builtinTimeToI, .{ .exact = 0 }));

    const to_f_sym = try vm.intern("to_f");
    try vm.time_class.module.methods.put(to_f_sym, value.MethodEntry.builtin(&builtinTimeToF, .{ .exact = 0 }));

    const to_r_sym = try vm.intern("to_r");
    try vm.time_class.module.methods.put(to_r_sym, value.MethodEntry.builtin(&builtinTimeToR, .{ .exact = 0 }));

    const nsec_sym = try vm.intern("nsec");
    const nsec_method = value.MethodEntry.builtin(&builtinTimeNsec, .{ .exact = 0 });
    try vm.time_class.module.methods.put(nsec_sym, nsec_method);

    const tv_nsec_sym = try vm.intern("tv_nsec");
    try vm.time_class.module.methods.put(tv_nsec_sym, nsec_method);

    const subsec_sym = try vm.intern("subsec");
    try vm.time_class.module.methods.put(subsec_sym, value.MethodEntry.builtin(&builtinTimeSubsec, .{ .exact = 0 }));

    const usec_method = value.MethodEntry.builtin(&builtinTimeUsec, .{ .exact = 0 });
    const usec_sym = try vm.intern("usec");
    try vm.time_class.module.methods.put(usec_sym, usec_method);
    const tv_usec_sym = try vm.intern("tv_usec");
    try vm.time_class.module.methods.put(tv_usec_sym, usec_method);

    const to_a_sym = try vm.intern("to_a");
    try vm.time_class.module.methods.put(to_a_sym, value.MethodEntry.builtin(&builtinTimeToA, .{ .exact = 0 }));

    const strftime_sym = try vm.intern("strftime");
    try vm.time_class.module.methods.put(strftime_sym, value.MethodEntry.builtin(&builtinTimeStrftime, .{ .exact = 1 }));

    const to_s_sym = try vm.intern("to_s");
    try vm.time_class.module.methods.put(to_s_sym, value.MethodEntry.builtin(&builtinTimeToS, .{ .exact = 0 }));

    const inspect_sym = try vm.intern("inspect");
    try vm.time_class.module.methods.put(inspect_sym, value.MethodEntry.builtin(&builtinTimeInspect, .{ .exact = 0 }));

    const hash_sym = try vm.intern("hash");
    try vm.time_class.module.methods.put(hash_sym, value.MethodEntry.builtin(&builtinTimeHash, .{ .exact = 0 }));

    const eql_sym = try vm.intern("eql?");
    try vm.time_class.module.methods.put(eql_sym, value.MethodEntry.builtin(&builtinTimeEql, .{ .exact = 1 }));

    const zone_sym = try vm.intern("zone");
    try vm.time_class.module.methods.put(zone_sym, value.MethodEntry.builtin(&builtinTimeZone, .{ .exact = 0 }));
}

fn floorDiv(numerator: i64, denominator: i64) i64 {
    var quotient = @divTrunc(numerator, denominator);
    const remainder = @rem(numerator, denominator);
    if (remainder != 0 and ((remainder < 0) != (denominator < 0))) {
        quotient -= 1;
    }
    return quotient;
}

fn floorMod(numerator: i64, denominator: i64) i64 {
    return numerator - floorDiv(numerator, denominator) * denominator;
}

fn integerIsZero(v: Value) bool {
    return if (v.isInteger()) v.toInteger() == 0 else v.toBigIntegerObject().value.eqlZero();
}

fn integerToI64(v: Value) i64 {
    return if (v.isInteger()) v.toInteger() else v.toBigIntegerObject().value.toInt(i64) catch unreachable;
}

fn exactParts(v: Value) struct { numerator: Value, denominator: Value } {
    if (v.isRational()) {
        const r = v.toRationalObject();
        return .{ .numerator = r.numerator, .denominator = r.denominator };
    }
    return .{ .numerator = v, .denominator = Value.integer(1) };
}

fn exactValue(vm: *VM, numerator: Value, denominator: Value) VMError!Value {
    if (denominator.isInteger() and denominator.toInteger() == 1) return numerator;
    const normalized = try vm.newRationalValues(numerator, denominator);
    const normalized_rational = normalized.toRationalObject();
    if (normalized_rational.denominator.isInteger() and normalized_rational.denominator.toInteger() == 1) {
        return normalized_rational.numerator;
    }
    return normalized;
}

fn exactAdd(vm: *VM, lhs: Value, rhs: Value) VMError!Value {
    const a = exactParts(lhs);
    const b = exactParts(rhs);
    const left = try vm.mulIntegerValues(a.numerator, b.denominator);
    const right = try vm.mulIntegerValues(b.numerator, a.denominator);
    return exactValue(vm, try vm.addIntegerValues(left, right), try vm.mulIntegerValues(a.denominator, b.denominator));
}

fn exactSub(vm: *VM, lhs: Value, rhs: Value) VMError!Value {
    const a = exactParts(lhs);
    const b = exactParts(rhs);
    const left = try vm.mulIntegerValues(a.numerator, b.denominator);
    const right = try vm.mulIntegerValues(b.numerator, a.denominator);
    return exactValue(vm, try vm.subIntegerValues(left, right), try vm.mulIntegerValues(a.denominator, b.denominator));
}

fn exactMul(vm: *VM, lhs: Value, rhs: Value) VMError!Value {
    const a = exactParts(lhs);
    const b = exactParts(rhs);
    return exactValue(vm, try vm.mulIntegerValues(a.numerator, b.numerator), try vm.mulIntegerValues(a.denominator, b.denominator));
}

fn exactDivByInteger(vm: *VM, value_: Value, divisor: i64) VMError!Value {
    const parts = exactParts(value_);
    return exactValue(vm, parts.numerator, try vm.mulIntegerValues(parts.denominator, Value.integer(divisor)));
}

fn exactCompare(vm: *VM, lhs: Value, rhs: Value) VMError!std.math.Order {
    const a = exactParts(lhs);
    const b = exactParts(rhs);
    return vm.compareIntegerValues(
        try vm.mulIntegerValues(a.numerator, b.denominator),
        try vm.mulIntegerValues(b.numerator, a.denominator),
    );
}

fn exactFloorDivByInteger(vm: *VM, value_: Value, divisor: i64) VMError!Value {
    const parts = exactParts(value_);
    const denominator = try vm.mulIntegerValues(parts.denominator, Value.integer(divisor));
    return vm.divFloorIntegerValues(parts.numerator, denominator);
}

fn exactToF64(value_: Value) f64 {
    const parts = exactParts(value_);
    return parts.numerator.integerToF64() / parts.denominator.integerToF64();
}

fn integerMod(vm: *VM, numerator: Value, denominator: i64) VMError!Value {
    const quotient = try vm.divFloorIntegerValues(numerator, Value.integer(denominator));
    return vm.subIntegerValues(numerator, try vm.mulIntegerValues(quotient, Value.integer(denominator)));
}

fn isLeapYear(vm: *VM, year: Value) VMError!bool {
    const mod4 = try integerMod(vm, year, 4);
    const mod100 = try integerMod(vm, year, 100);
    const mod400 = try integerMod(vm, year, 400);
    return integerIsZero(mod4) and (!integerIsZero(mod100) or integerIsZero(mod400));
}

fn daysInMonth(vm: *VM, year: Value, month: u8) VMError!u8 {
    return switch (month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => if (try isLeapYear(vm, year)) 29 else 28,
        else => 0,
    };
}

fn daysFromCivil(vm: *VM, year: Value, month: u8, day: u8) VMError!Value {
    var adjusted_year = year;
    if (month <= 2) adjusted_year = try vm.subIntegerValues(adjusted_year, Value.integer(1));
    const era = try vm.divFloorIntegerValues(adjusted_year, Value.integer(400));
    const year_of_era = try vm.subIntegerValues(adjusted_year, try vm.mulIntegerValues(era, Value.integer(400)));
    const month_i64: i64 = @intCast(month);
    const day_i64: i64 = @intCast(day);
    const month_prime = month_i64 + (if (month > 2) @as(i64, -3) else @as(i64, 9));
    const day_of_year = floorDiv(153 * month_prime + 2, 5) + day_i64 - 1;
    var day_of_era = try vm.mulIntegerValues(year_of_era, Value.integer(365));
    day_of_era = try vm.addIntegerValues(day_of_era, try vm.divFloorIntegerValues(year_of_era, Value.integer(4)));
    day_of_era = try vm.subIntegerValues(day_of_era, try vm.divFloorIntegerValues(year_of_era, Value.integer(100)));
    day_of_era = try vm.addIntegerValues(day_of_era, Value.integer(day_of_year));
    return vm.subIntegerValues(
        try vm.addIntegerValues(try vm.mulIntegerValues(era, Value.integer(146097)), day_of_era),
        Value.integer(719468),
    );
}

fn civilFromDays(vm: *VM, days_since_epoch: Value) VMError!CivilDate {
    const shifted = try vm.addIntegerValues(days_since_epoch, Value.integer(719468));
    const era = try vm.divFloorIntegerValues(shifted, Value.integer(146097));
    const day_of_era_value = try vm.subIntegerValues(shifted, try vm.mulIntegerValues(era, Value.integer(146097)));
    const day_of_era = integerToI64(day_of_era_value);
    const year_of_era = floorDiv(day_of_era - floorDiv(day_of_era, 1460) + floorDiv(day_of_era, 36524) - floorDiv(day_of_era, 146096), 365);
    var year = try vm.addIntegerValues(Value.integer(year_of_era), try vm.mulIntegerValues(era, Value.integer(400)));
    const day_of_year = day_of_era - (365 * year_of_era + floorDiv(year_of_era, 4) - floorDiv(year_of_era, 100));
    const month_prime = floorDiv(5 * day_of_year + 2, 153);
    const day = day_of_year - floorDiv(153 * month_prime + 2, 5) + 1;
    const month = month_prime + (if (month_prime < 10) @as(i64, 3) else @as(i64, -9));
    if (month <= 2) year = try vm.addIntegerValues(year, Value.integer(1));
    return .{
        .year = year,
        .month = @intCast(month),
        .day = @intCast(day),
    };
}

// Compute wall-clock parts for an epoch_nanoseconds value that already has the
// UTC offset applied (i.e. epoch_nanoseconds + utc_offset_nanos).
fn timeParts(vm: *VM, adjusted_timew: Value) VMError!TimeParts {
    const total_seconds = try exactFloorDivByInteger(vm, adjusted_timew, nanos_per_second);
    const whole_nanos = try vm.mulIntegerValues(total_seconds, Value.integer(nanos_per_second));
    const subsecond = try exactSub(vm, adjusted_timew, whole_nanos);
    const nanosecond_value = try exactFloorDivByInteger(vm, subsecond, 1);
    const nanosecond: u32 = @intCast(integerToI64(nanosecond_value));
    const day_count = try vm.divFloorIntegerValues(total_seconds, Value.integer(seconds_per_day));
    const seconds_of_day_value = try vm.subIntegerValues(total_seconds, try vm.mulIntegerValues(day_count, Value.integer(seconds_per_day)));
    const seconds_of_day = integerToI64(seconds_of_day_value);
    const civil = try civilFromDays(vm, day_count);
    const hour: u8 = @intCast(@divTrunc(seconds_of_day, seconds_per_hour));
    const minute: u8 = @intCast(@divTrunc(@rem(seconds_of_day, seconds_per_hour), seconds_per_minute));
    const second: u8 = @intCast(@rem(seconds_of_day, seconds_per_minute));
    const first_day = try daysFromCivil(vm, civil.year, 1, 1);
    const year_day_value = try vm.addIntegerValues(try vm.subIntegerValues(day_count, first_day), Value.integer(1));
    const year_day: u16 = @intCast(integerToI64(year_day_value));
    const weekday_value = try integerMod(vm, try vm.addIntegerValues(day_count, Value.integer(4)), 7);
    const weekday: u8 = @intCast(integerToI64(weekday_value));
    return .{
        .year = civil.year,
        .month = civil.month,
        .day = civil.day,
        .hour = hour,
        .minute = minute,
        .second = second,
        .nanosecond = nanosecond,
        .weekday = weekday,
        .year_day = year_day,
    };
}

fn timePartsFor(vm: *VM, t: *const value.TimeObject) VMError!TimeParts {
    return timeParts(vm, try exactAdd(vm, t.timew, Value.integer(t.utc_offset_nanos)));
}

fn coerceIntegerComponent(vm: *VM, arg: Value) VMError!i64 {
    return arg.coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "no implicit conversion into Integer",
        "bignum too big to convert into `long`",
    );
}

fn coerceIntegerComponentValue(vm: *VM, arg: Value) VMError!Value {
    return arg.coerceToIntegerValue(
        vm,
        "no implicit conversion into Integer",
        "no implicit conversion into Integer",
    );
}

fn coerceExactNumeric(vm: *VM, arg: Value) VMError!Value {
    if (arg.isInteger() or arg.isBigInteger() or arg.isRational()) return arg;
    if (arg.isFloat()) {
        const f = arg.toFloatObject().val;
        if (std.math.isNan(f)) return vm.raiseExceptionFmt(vm.float_domain_error_class, "NaN", .{});
        if (std.math.isInf(f)) {
            return vm.raiseExceptionFmt(vm.float_domain_error_class, "{s}Infinity", .{if (f < 0) "-" else ""});
        }
        const parts = try rational.floatToRationalParts(vm, f);
        return exactValue(vm, parts.numerator, parts.denominator);
    }
    if (try vm.checkCallMethodByName(arg, "to_r", false, &.{}, null)) |converted| {
        if ((converted.isInteger() or converted.isBigInteger() or converted.isRational()) and
            try vm.respondsToMethodByName(arg, "to_int", true))
        {
            return converted;
        }
    }
    if (try vm.checkCallMethodByName(arg, "to_int", false, &.{}, null)) |converted| {
        if (converted.isInteger() or converted.isBigInteger()) return converted;
    }
    return vm.raiseExceptionFmt(vm.type_error_class, "argument is not numeric", .{});
}

fn epochSecondsForTimezone(vm: *VM, timew: Value) VMError!i64 {
    const seconds = try exactFloorDivByInteger(vm, timew, nanos_per_second);
    if (seconds.isInteger()) return seconds.toInteger();
    return seconds.toBigIntegerObject().value.toInt(i64) catch
        if (seconds.toBigIntegerObject().value.isPositive()) std.math.maxInt(i64) else std.math.minInt(i64);
}

fn validateUtcComponents(vm: *VM, year: Value, month: i64, day: i64, hour: i64, minute: i64, second: i64) VMError!void {
    if (month < 1 or month > 12) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid month", .{});
    }
    const max_day = try daysInMonth(vm, year, @intCast(month));
    if (day < 1 or day > max_day) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid day", .{});
    }
    if (hour < 0 or hour > 23 or minute < 0 or minute > 59 or second < 0 or second > 59) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid time", .{});
    }
}

fn epochNanosecondsFromUtcComponents(vm: *VM, year: Value, month: i64, day: i64, hour: i64, minute: i64, second: i64, nanosecond: u32) VMError!Value {
    const day_count = try daysFromCivil(vm, year, @intCast(month), @intCast(day));
    var total_seconds = try vm.mulIntegerValues(day_count, Value.integer(seconds_per_day));
    total_seconds = try vm.addIntegerValues(total_seconds, Value.integer(hour * seconds_per_hour + minute * seconds_per_minute + second));
    return vm.addIntegerValues(try vm.mulIntegerValues(total_seconds, Value.integer(nanos_per_second)), Value.integer(nanosecond));
}

fn parseMarshalDumpedUtcNanoseconds(vm: *VM, raw: []const u8) VMError!?Value {
    if (raw.len < 8) return null;

    var packed_date = std.mem.readInt(u32, raw[0..4], .little);
    const packed_time = std.mem.readInt(u32, raw[4..8], .little);
    if ((packed_date & (@as(u32, 1) << 31)) == 0) return null;

    packed_date &= ~(@as(u32, 1) << 31);

    var year: i64 = 1900 + @as(i64, (packed_date >> 14) & 0xffff);
    var month: i64 = 1 + @as(i64, (packed_date >> 10) & 0xf);
    if (month > 12) {
        month -= 12;
        year += 1;
    }

    const day: i64 = @as(i64, (packed_date >> 5) & 0x1f);
    const hour: i64 = @as(i64, packed_date & 0x1f);
    const minute: i64 = @as(i64, (packed_time >> 26) & 0x3f);
    const second: i64 = @as(i64, (packed_time >> 20) & 0x3f);
    const microsecond: u32 = @intCast(packed_time & 0xfffff);

    if (month < 1 or month > 12) return null;
    if (day < 1 or day > try daysInMonth(vm, Value.integer(year), @intCast(month))) return null;
    if (hour > 23 or minute > 59 or second > 59) return null;

    return try epochNanosecondsFromUtcComponents(vm, Value.integer(year), month, day, hour, minute, second, microsecond * 1000);
}

fn currentEpochNanoseconds() i64 {
    var timespec: std.posix.timespec = undefined;
    if (clock_gettime(.REALTIME, &timespec) != 0) {
        return 0;
    }
    const seconds: i128 = @intCast(timespec.sec);
    const nanoseconds: i128 = @intCast(timespec.nsec);
    return @intCast(seconds * nanos_per_second + nanoseconds);
}

fn parseStrftimeUtcOffsetSeconds(bytes: []const u8) ?i64 {
    if (bytes.len != 5) return null;
    const sign: i64 = switch (bytes[0]) {
        '+' => 1,
        '-' => -1,
        else => return null,
    };

    var hours: i64 = 0;
    var minutes: i64 = 0;
    for (bytes[1..3]) |byte| {
        if (!std.ascii.isDigit(byte)) return null;
        hours = hours * 10 + (byte - '0');
    }
    for (bytes[3..5]) |byte| {
        if (!std.ascii.isDigit(byte)) return null;
        minutes = minutes * 10 + (byte - '0');
    }
    return sign * (hours * seconds_per_hour + minutes * seconds_per_minute);
}

fn zoneinfoUtcOffsetNanos(io: std.Io, epoch_seconds: i64) ?i64 {
    var tz = std.mem.span(std.c.getenv("TZ") orelse return null);
    if (tz.len == 0) return null;
    if (tz[0] == ':') {
        tz = tz[1..];
        if (tz.len == 0) return null;
    }
    if (std.mem.indexOf(u8, tz, "..") != null) return null;

    var path_buf: [512]u8 = undefined;
    const path = if (std.mem.startsWith(u8, tz, "/"))
        tz
    else if (std.mem.indexOfScalar(u8, tz, '/') != null)
        std.fmt.bufPrint(&path_buf, "/usr/share/zoneinfo/{s}", .{tz}) catch return null
    else
        return null;

    const allocator = std.heap.page_allocator;
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1 << 20)) catch return null;
    defer allocator.free(bytes);

    var in_stream: std.Io.Reader = .fixed(bytes);
    var tz_file = std.Tz.parse(allocator, &in_stream) catch return null;
    defer tz_file.deinit();

    var selected_timetype = &tz_file.timetypes[0];
    if (tz_file.transitions.len != 0) {
        var found_transition = false;
        for (tz_file.transitions) |transition| {
            if (epoch_seconds < transition.ts) break;
            selected_timetype = transition.timetype;
            found_transition = true;
        }
        if (!found_transition) {
            for (tz_file.timetypes) |*timetype| {
                if (!timetype.isDst()) {
                    selected_timetype = timetype;
                    break;
                }
            }
        }
    }

    return @as(i64, selected_timetype.offset) * nanos_per_second;
}

// Get the system local UTC offset in nanoseconds for the given epoch second.
fn localUtcOffsetNanos(io: std.Io, epoch_seconds: i64) i64 {
    if (zoneinfoUtcOffsetNanos(io, epoch_seconds)) |offset_nanos| {
        return offset_nanos;
    }
    tzset(); // pick up any TZ environment variable change
    var tm: CStructTm = undefined;
    const t: c_time_t = epoch_seconds;
    if (localtime_r(&t, &tm) == null) return 0;
    var offset_buf: [16]u8 = undefined;
    const offset_len = strftime(offset_buf[0..].ptr, offset_buf.len, "%z", &tm);
    if (offset_len != 0) {
        if (parseStrftimeUtcOffsetSeconds(offset_buf[0..offset_len])) |offset_seconds| {
            return offset_seconds * nanos_per_second;
        }
    }
    const offset_seconds: i64 = @intCast(tm.tm_gmtoff);
    return offset_seconds * nanos_per_second;
}

fn constructUtcTime(vm: *VM, class_obj: *value.ClassObject, args: []Value) VMError!Value {
    if (args.len == 0 or args.len > 7) {
        try vm.requireArgCountRange(args, 1, 7);
        unreachable;
    }

    const year = try coerceIntegerComponentValue(vm, args[0]);
    const month = if (args.len >= 2 and !args[1].isNil()) try coerceIntegerComponent(vm, args[1]) else 1;
    const day = if (args.len >= 3 and !args[2].isNil()) try coerceIntegerComponent(vm, args[2]) else 1;
    const hour = if (args.len >= 4 and !args[3].isNil()) try coerceIntegerComponent(vm, args[3]) else 0;
    const minute = if (args.len >= 5 and !args[4].isNil()) try coerceIntegerComponent(vm, args[4]) else 0;
    const second_exact = if (args.len >= 6 and !args[5].isNil()) try coerceExactNumeric(vm, args[5]) else Value.integer(0);
    const second_value = try exactFloorDivByInteger(vm, second_exact, 1);
    const second = integerToI64(second_value);
    const second_fraction = try exactMul(vm, try exactSub(vm, second_exact, second_value), Value.integer(nanos_per_second));
    const nanosecond = if (args.len >= 7 and !args[6].isNil()) blk: {
        const usec = try coerceIntegerComponent(vm, args[6]);
        break :blk @as(u32, @intCast(usec * 1000));
    } else 0;

    try validateUtcComponents(vm, year, month, day, hour, minute, second);
    const epoch_nanos = try exactAdd(vm, try epochNanosecondsFromUtcComponents(vm, year, month, day, hour, minute, second, nanosecond), second_fraction);
    return vm.newTime(class_obj, epoch_nanos);
}

// Construct a local time. args = (year[, month[, day[, hour[, min[, sec[, usec_with_frac]]]]]]])
// The components describe wall clock time in local timezone; we convert to UTC epoch.
fn constructLocalTime(vm: *VM, class_obj: *value.ClassObject, args: []Value) VMError!Value {
    if (args.len == 0 or args.len > 7) {
        try vm.requireArgCountRange(args, 1, 7);
        unreachable;
    }

    const year = try coerceIntegerComponentValue(vm, args[0]);
    const month = if (args.len >= 2 and !args[1].isNil()) try coerceIntegerComponent(vm, args[1]) else 1;
    const day = if (args.len >= 3 and !args[2].isNil()) try coerceIntegerComponent(vm, args[2]) else 1;
    const hour = if (args.len >= 4 and !args[3].isNil()) try coerceIntegerComponent(vm, args[3]) else 0;
    const minute = if (args.len >= 5 and !args[4].isNil()) try coerceIntegerComponent(vm, args[4]) else 0;
    const second_exact = if (args.len >= 6 and !args[5].isNil()) try coerceExactNumeric(vm, args[5]) else Value.integer(0);
    const second_value = try exactFloorDivByInteger(vm, second_exact, 1);
    const second = integerToI64(second_value);
    const second_fraction = try exactMul(vm, try exactSub(vm, second_exact, second_value), Value.integer(nanos_per_second));
    const nanosecond: u32 = if (args.len >= 7 and !args[6].isNil()) blk: {
        const usec = try coerceIntegerComponent(vm, args[6]);
        break :blk @as(u32, @intCast(usec * 1000));
    } else 0;

    try validateUtcComponents(vm, year, month, day, hour, minute, second);
    // Compute as if UTC, then adjust by local timezone offset.
    const utc_epoch_nanos = try exactAdd(vm, try epochNanosecondsFromUtcComponents(vm, year, month, day, hour, minute, second, nanosecond), second_fraction);
    const utc_epoch_seconds = try epochSecondsForTimezone(vm, utc_epoch_nanos);
    const offset_nanos = localUtcOffsetNanos(vm.io, utc_epoch_seconds);
    // epoch_nanoseconds is the true UTC moment; components are local wall clock.
    const epoch_nanos = try exactSub(vm, utc_epoch_nanos, Value.integer(offset_nanos));
    return vm.newTimeLocal(class_obj, epoch_nanos, offset_nanos);
}

// Parse a UTC offset string: "+HH:MM", "+HHMM", "+HH:MM:SS", "+HHMMSS",
// "UTC", or single letter military zone A-I, K-Z (excluding J).
// Returns offset in nanoseconds.
// On error returns null; vm has already raised ArgumentError.
fn parseUtcOffsetString(vm: *VM, s: []const u8) VMError!i64 {
    // "UTC" → 0
    if (std.mem.eql(u8, s, "UTC")) return 0;

    // Single military letter A-I=+1..+9, K=+10, L=+11, M=+12, N=-1..Z=-12 (J excluded)
    if (s.len == 1) {
        const ch = s[0];
        const offset_hours: i64 = switch (ch) {
            'A' => 1,
            'B' => 2,
            'C' => 3,
            'D' => 4,
            'E' => 5,
            'F' => 6,
            'G' => 7,
            'H' => 8,
            'I' => 9,
            'K' => 10,
            'L' => 11,
            'M' => 12,
            'N' => -1,
            'O' => -2,
            'P' => -3,
            'Q' => -4,
            'R' => -5,
            'S' => -6,
            'T' => -7,
            'U' => -8,
            'V' => -9,
            'W' => -10,
            'X' => -11,
            'Y' => -12,
            'Z' => 0,
            else => {
                return vm.raiseExceptionFmt(
                    vm.argument_error_class,
                    "\"+HH:MM\", \"-HH:MM\", \"UTC\" or \"A\"..\"I\",\"K\"..\"Z\" expected for utc_offset: {s}",
                    .{s},
                );
            },
        };
        return offset_hours * seconds_per_hour * nanos_per_second;
    }

    if (s.len < 3) {
        return vm.raiseExceptionFmt(
            vm.argument_error_class,
            "\"+HH:MM\", \"-HH:MM\", \"UTC\" or \"A\"..\"I\",\"K\"..\"Z\" expected for utc_offset: {s}",
            .{s},
        );
    }

    const sign: i64 = switch (s[0]) {
        '+' => 1,
        '-' => -1,
        else => {
            return vm.raiseExceptionFmt(
                vm.argument_error_class,
                "\"+HH:MM\", \"-HH:MM\", \"UTC\" or \"A\"..\"I\",\"K\"..\"Z\" expected for utc_offset: {s}",
                .{s},
            );
        },
    };

    const rest = s[1..];
    var hours: i64 = 0;
    var minutes: i64 = 0;
    var secs: i64 = 0;

    // Colon-separated: HH:MM or HH:MM:SS
    if (rest.len == 5 and rest[2] == ':') {
        // +HH:MM
        hours = parseDigits(rest[0..2]) orelse return vm.raiseExceptionFmt(
            vm.argument_error_class,
            "\"+HH:MM\", \"-HH:MM\", \"UTC\" or \"A\"..\"I\",\"K\"..\"Z\" expected for utc_offset: {s}",
            .{s},
        );
        minutes = parseDigits(rest[3..5]) orelse return vm.raiseExceptionFmt(
            vm.argument_error_class,
            "\"+HH:MM\", \"-HH:MM\", \"UTC\" or \"A\"..\"I\",\"K\"..\"Z\" expected for utc_offset: {s}",
            .{s},
        );
    } else if (rest.len == 8 and rest[2] == ':' and rest[5] == ':') {
        // +HH:MM:SS
        hours = parseDigits(rest[0..2]) orelse return vm.raiseExceptionFmt(
            vm.argument_error_class,
            "\"+HH:MM\", \"-HH:MM\", \"UTC\" or \"A\"..\"I\",\"K\"..\"Z\" expected for utc_offset: {s}",
            .{s},
        );
        minutes = parseDigits(rest[3..5]) orelse return vm.raiseExceptionFmt(
            vm.argument_error_class,
            "\"+HH:MM\", \"-HH:MM\", \"UTC\" or \"A\"..\"I\",\"K\"..\"Z\" expected for utc_offset: {s}",
            .{s},
        );
        secs = parseDigits(rest[6..8]) orelse return vm.raiseExceptionFmt(
            vm.argument_error_class,
            "\"+HH:MM\", \"-HH:MM\", \"UTC\" or \"A\"..\"I\",\"K\"..\"Z\" expected for utc_offset: {s}",
            .{s},
        );
    } else if (rest.len == 4) {
        // +HHMM
        hours = parseDigits(rest[0..2]) orelse return vm.raiseExceptionFmt(
            vm.argument_error_class,
            "\"+HH:MM\", \"-HH:MM\", \"UTC\" or \"A\"..\"I\",\"K\"..\"Z\" expected for utc_offset: {s}",
            .{s},
        );
        minutes = parseDigits(rest[2..4]) orelse return vm.raiseExceptionFmt(
            vm.argument_error_class,
            "\"+HH:MM\", \"-HH:MM\", \"UTC\" or \"A\"..\"I\",\"K\"..\"Z\" expected for utc_offset: {s}",
            .{s},
        );
    } else if (rest.len == 6) {
        // +HHMMSS
        hours = parseDigits(rest[0..2]) orelse return vm.raiseExceptionFmt(
            vm.argument_error_class,
            "\"+HH:MM\", \"-HH:MM\", \"UTC\" or \"A\"..\"I\",\"K\"..\"Z\" expected for utc_offset: {s}",
            .{s},
        );
        minutes = parseDigits(rest[2..4]) orelse return vm.raiseExceptionFmt(
            vm.argument_error_class,
            "\"+HH:MM\", \"-HH:MM\", \"UTC\" or \"A\"..\"I\",\"K\"..\"Z\" expected for utc_offset: {s}",
            .{s},
        );
        secs = parseDigits(rest[4..6]) orelse return vm.raiseExceptionFmt(
            vm.argument_error_class,
            "\"+HH:MM\", \"-HH:MM\", \"UTC\" or \"A\"..\"I\",\"K\"..\"Z\" expected for utc_offset: {s}",
            .{s},
        );
    } else {
        return vm.raiseExceptionFmt(
            vm.argument_error_class,
            "\"+HH:MM\", \"-HH:MM\", \"UTC\" or \"A\"..\"I\",\"K\"..\"Z\" expected for utc_offset: {s}",
            .{s},
        );
    }

    if (hours >= 24) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "utc_offset out of range", .{});
    }
    if (minutes >= 60) {
        return vm.raiseExceptionFmt(
            vm.argument_error_class,
            "\"+HH:MM\", \"-HH:MM\", \"UTC\" or \"A\"..\"I\",\"K\"..\"Z\" expected for utc_offset: {s}",
            .{s},
        );
    }
    if (secs >= 60) {
        return vm.raiseExceptionFmt(
            vm.argument_error_class,
            "\"+HH:MM\", \"-HH:MM\", \"UTC\" or \"A\"..\"I\",\"K\"..\"Z\" expected for utc_offset: {s}",
            .{s},
        );
    }

    const total_seconds = sign * (hours * seconds_per_hour + minutes * seconds_per_minute + secs);
    return total_seconds * nanos_per_second;
}

fn parseDigits(bytes: []const u8) ?i64 {
    var v: i64 = 0;
    for (bytes) |b| {
        if (!std.ascii.isDigit(b)) return null;
        v = v * 10 + (b - '0');
    }
    return v;
}

// Parse the utc_offset argument for localtime/Time.new:
//   Integer/Float → seconds, Rational → seconds (rational), String → parsed.
// Returns offset in nanoseconds.
fn parseUtcOffsetArg(vm: *VM, arg: Value) VMError!i64 {
    if (arg.isInteger()) {
        const secs = arg.toInteger();
        if (secs <= -86400 or secs >= 86400) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "utc_offset out of range", .{});
        }
        return secs * nanos_per_second;
    }
    if (arg.isFloat()) {
        const secs_f = arg.toFloatObject().val;
        if (secs_f <= -86400.0 or secs_f >= 86400.0) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "utc_offset out of range", .{});
        }
        return @as(i64, @intFromFloat(secs_f * @as(f64, @floatFromInt(nanos_per_second))));
    }
    if (arg.isRational()) {
        const rat = arg.toRationalObject();
        const num = rat.numerator.toInteger();
        const den = rat.denominator.toInteger();
        // offset_nanos = (num / den) * nanos_per_second
        const nanos = @divTrunc(num * nanos_per_second, den);
        const secs_approx = @divTrunc(nanos, nanos_per_second);
        if (secs_approx <= -86400 or secs_approx >= 86400) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "utc_offset out of range", .{});
        }
        return nanos;
    }
    // String/Symbol: parse directly without going through object coercion.
    if (arg.isString() or arg.isSymbol()) {
        const s = arg.toStringObject();
        if (!s.encoding.isAsciiCompatible()) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "argument is not ASCII-compatible encoding", .{});
        }
        return try parseUtcOffsetString(vm, s.str);
    }
    // Try to_r first (for mock_numeric), then to_int, then to_str.
    // Uses checkCallMethodByName so singleton methods (e.g. from should_receive) are found.
    if (try vm.checkCallMethodByName(arg, "to_r", false, &.{}, null)) |rat_val| {
        if (rat_val.isRational()) {
            const rat = rat_val.toRationalObject();
            const num = rat.numerator.toInteger();
            const den = rat.denominator.toInteger();
            const nanos = @divTrunc(num * nanos_per_second, den);
            const secs_approx = @divTrunc(nanos, nanos_per_second);
            if (secs_approx <= -86400 or secs_approx >= 86400) {
                return vm.raiseExceptionFmt(vm.argument_error_class, "utc_offset out of range", .{});
            }
            return nanos;
        }
    }
    if (try vm.checkCallMethodByName(arg, "to_int", false, &.{}, null)) |int_val| {
        if (int_val.isInteger()) {
            const secs = int_val.toInteger();
            if (secs <= -86400 or secs >= 86400) {
                return vm.raiseExceptionFmt(vm.argument_error_class, "utc_offset out of range", .{});
            }
            return secs * nanos_per_second;
        }
    }
    if (try vm.checkCallMethodByName(arg, "to_str", false, &.{}, null)) |str_val| {
        if (str_val.isString()) {
            const s = str_val.toStringObject();
            if (!s.encoding.isAsciiCompatible()) {
                return vm.raiseExceptionFmt(vm.argument_error_class, "argument is not ASCII-compatible encoding", .{});
            }
            return try parseUtcOffsetString(vm, s.str);
        }
    }
    return vm.raiseExceptionFmt(vm.argument_error_class, "invalid utc_offset", .{});
}

fn parseFixedDigits(bytes: []const u8, start: usize, len: usize) ?i64 {
    if (start + len > bytes.len) return null;
    var value_i64: i64 = 0;
    for (bytes[start .. start + len]) |byte| {
        if (!std.ascii.isDigit(byte)) return null;
        value_i64 = value_i64 * 10 + (byte - '0');
    }
    return value_i64;
}

fn parseFractionalNanoseconds(bytes: []const u8, start: usize, end: usize) ?u32 {
    if (start >= end) return null;
    var value_i64: i64 = 0;
    var digits_seen: usize = 0;
    var index = start;
    while (index < end and std.ascii.isDigit(bytes[index])) : (index += 1) {
        if (digits_seen < 9) {
            value_i64 = value_i64 * 10 + (bytes[index] - '0');
        }
        digits_seen += 1;
    }
    if (digits_seen == 0 or index != end) return null;
    while (digits_seen < 9) : (digits_seen += 1) {
        value_i64 *= 10;
    }
    return @intCast(value_i64);
}

fn parseTimeString(vm: *VM, raw: []const u8) VMError!Value {
    const bytes = std.mem.trim(u8, raw, " \t\r\n");
    if (bytes.len < 10) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid time", .{});
    }

    const year = parseFixedDigits(bytes, 0, 4) orelse return vm.raiseExceptionFmt(vm.argument_error_class, "invalid time", .{});
    if (bytes[4] != '-') return vm.raiseExceptionFmt(vm.argument_error_class, "invalid time", .{});
    const month = parseFixedDigits(bytes, 5, 2) orelse return vm.raiseExceptionFmt(vm.argument_error_class, "invalid time", .{});
    if (bytes[7] != '-') return vm.raiseExceptionFmt(vm.argument_error_class, "invalid time", .{});
    const day = parseFixedDigits(bytes, 8, 2) orelse return vm.raiseExceptionFmt(vm.argument_error_class, "invalid time", .{});

    if (bytes.len == 10) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "date-only strings are not supported", .{});
    }
    if (bytes.len < 19 or (bytes[10] != ' ' and bytes[10] != 'T')) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid time", .{});
    }

    const hour = parseFixedDigits(bytes, 11, 2) orelse return vm.raiseExceptionFmt(vm.argument_error_class, "invalid time", .{});
    if (bytes[13] != ':') return vm.raiseExceptionFmt(vm.argument_error_class, "invalid time", .{});
    const minute = parseFixedDigits(bytes, 14, 2) orelse return vm.raiseExceptionFmt(vm.argument_error_class, "invalid time", .{});
    if (bytes[16] != ':') return vm.raiseExceptionFmt(vm.argument_error_class, "invalid time", .{});
    const second = parseFixedDigits(bytes, 17, 2) orelse return vm.raiseExceptionFmt(vm.argument_error_class, "invalid time", .{});

    var nanosecond: u32 = 0;
    var index: usize = 19;
    if (index < bytes.len and bytes[index] == '.') {
        index += 1;
        var fraction_end = index;
        while (fraction_end < bytes.len and std.ascii.isDigit(bytes[fraction_end])) : (fraction_end += 1) {}
        nanosecond = parseFractionalNanoseconds(bytes, index, fraction_end) orelse return vm.raiseExceptionFmt(vm.argument_error_class, "invalid time", .{});
        index = fraction_end;
    }

    if (index < bytes.len and bytes[index] == ' ') {
        index += 1;
    }
    if (index < bytes.len) {
        const zone = bytes[index..];
        if (!(std.mem.eql(u8, zone, "Z") or std.mem.eql(u8, zone, "UTC") or std.mem.eql(u8, zone, "+00:00"))) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "unsupported time zone", .{});
        }
    }

    try validateUtcComponents(vm, Value.integer(year), month, day, hour, minute, second);
    return epochNanosecondsFromUtcComponents(vm, Value.integer(year), month, day, hour, minute, second, nanosecond);
}

fn appendPaddedDecimal(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value_in: anytype, width: usize) VMError!void {
    const value_i64: i64 = @intCast(value_in);
    var buffer: [32]u8 = undefined;
    const digits = std.fmt.bufPrint(&buffer, "{d}", .{value_i64}) catch return error.Fatal;
    if (digits.len < width) {
        for (0..width - digits.len) |_| {
            out.append(allocator, '0') catch return error.Fatal;
        }
    }
    out.appendSlice(allocator, digits) catch return error.Fatal;
}

fn appendPaddedIntegerValue(out: *std.ArrayList(u8), vm: *VM, integer: Value, width: usize) VMError!void {
    const negative = (try vm.compareIntegerValues(integer, Value.integer(0))) == .lt;
    const magnitude = if (negative) try vm.mulIntegerValues(integer, Value.integer(-1)) else integer;
    var buf: std.Io.Writer.Allocating = .init(vm.allocator);
    defer buf.deinit();
    magnitude.format(&buf.writer) catch return error.Fatal;
    if (negative) out.append(vm.allocator, '-') catch return error.Fatal;
    if (buf.written().len < width) {
        for (0..width - buf.written().len) |_| out.append(vm.allocator, '0') catch return error.Fatal;
    }
    out.appendSlice(vm.allocator, buf.written()) catch return error.Fatal;
}

fn appendNanosecondDigits(out: *std.ArrayList(u8), allocator: std.mem.Allocator, nanoseconds: u32, width: usize) VMError!void {
    var buffer: [16]u8 = undefined;
    const digits = std.fmt.bufPrint(&buffer, "{d}", .{nanoseconds}) catch return error.Fatal;
    const pad = if (digits.len < 9) 9 - digits.len else 0;
    var full: [9]u8 = [_]u8{'0'} ** 9;
    @memcpy(full[pad..], digits[0 .. 9 - pad]);

    if (width <= 9) {
        out.appendSlice(allocator, full[0..width]) catch return error.Fatal;
        return;
    }

    out.appendSlice(allocator, &full) catch return error.Fatal;
    for (0..width - 9) |_| {
        out.append(allocator, '0') catch return error.Fatal;
    }
}

// Append the UTC offset portion of a time's to_s: " UTC" or " +HH:MM".
fn appendUtcOffsetStr(out: *std.ArrayList(u8), allocator: std.mem.Allocator, t: *const value.TimeObject) VMError!void {
    if (t.is_utc) {
        out.appendSlice(allocator, " UTC") catch return error.Fatal;
        return;
    }
    const total_seconds = @divTrunc(t.utc_offset_nanos, nanos_per_second);
    const sign: u8 = if (total_seconds >= 0) '+' else '-';
    const abs_seconds = if (total_seconds >= 0) total_seconds else -total_seconds;
    const off_h = @divTrunc(abs_seconds, seconds_per_hour);
    const off_m = @divTrunc(@rem(abs_seconds, seconds_per_hour), seconds_per_minute);
    var buf: [16]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, " {c}{d:0>2}:{d:0>2}", .{ sign, @as(u64, @intCast(off_h)), @as(u64, @intCast(off_m)) }) catch return error.Fatal;
    out.appendSlice(allocator, s) catch return error.Fatal;
}

fn timeStringValue(vm: *VM, receiver: Value) VMError!Value {
    const t = receiver.toTimeObject();
    const parts = try timePartsFor(vm, t);
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.allocator);
    try appendPaddedIntegerValue(&out, vm, parts.year, 4);
    out.append(vm.allocator, '-') catch return error.Fatal;
    try appendPaddedDecimal(&out, vm.allocator, parts.month, 2);
    out.append(vm.allocator, '-') catch return error.Fatal;
    try appendPaddedDecimal(&out, vm.allocator, parts.day, 2);
    out.appendSlice(vm.allocator, " ") catch return error.Fatal;
    try appendPaddedDecimal(&out, vm.allocator, parts.hour, 2);
    out.append(vm.allocator, ':') catch return error.Fatal;
    try appendPaddedDecimal(&out, vm.allocator, parts.minute, 2);
    out.append(vm.allocator, ':') catch return error.Fatal;
    try appendPaddedDecimal(&out, vm.allocator, parts.second, 2);
    try appendUtcOffsetStr(&out, vm.allocator, t);
    return vm.newString(out.items, false);
}

fn buildStrftimeValue(vm: *VM, receiver: Value, format_bytes: []const u8) VMError!Value {
    const t = receiver.toTimeObject();
    const parts = try timePartsFor(vm, t);
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.allocator);

    var index: usize = 0;
    while (index < format_bytes.len) {
        if (format_bytes[index] != '%') {
            out.append(vm.allocator, format_bytes[index]) catch return error.Fatal;
            index += 1;
            continue;
        }

        index += 1;
        if (index >= format_bytes.len) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "incomplete strftime directive", .{});
        }

        var dash_flag = false;
        while (index < format_bytes.len) : (index += 1) {
            switch (format_bytes[index]) {
                '-' => dash_flag = true,
                '0', '_' => {},
                else => break,
            }
        }

        var colon_count: usize = 0;
        while (index < format_bytes.len and format_bytes[index] == ':') : (index += 1) {
            colon_count += 1;
        }

        var width: usize = 0;
        var saw_width = false;
        while (index < format_bytes.len and std.ascii.isDigit(format_bytes[index])) : (index += 1) {
            saw_width = true;
            width = width * 10 + (format_bytes[index] - '0');
        }
        if (index >= format_bytes.len) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "incomplete strftime directive", .{});
        }

        const directive = format_bytes[index];
        index += 1;
        switch (directive) {
            '%' => out.append(vm.allocator, '%') catch return error.Fatal,
            'Y' => try appendPaddedIntegerValue(&out, vm, parts.year, 4),
            'm' => try appendPaddedDecimal(&out, vm.allocator, parts.month, 2),
            'd' => try appendPaddedDecimal(&out, vm.allocator, parts.day, 2),
            'H' => try appendPaddedDecimal(&out, vm.allocator, parts.hour, 2),
            'M' => try appendPaddedDecimal(&out, vm.allocator, parts.minute, 2),
            'S' => try appendPaddedDecimal(&out, vm.allocator, parts.second, 2),
            'N' => try appendNanosecondDigits(&out, vm.allocator, parts.nanosecond, if (saw_width) width else 9),
            'F' => {
                try appendPaddedIntegerValue(&out, vm, parts.year, 4);
                out.append(vm.allocator, '-') catch return error.Fatal;
                try appendPaddedDecimal(&out, vm.allocator, parts.month, 2);
                out.append(vm.allocator, '-') catch return error.Fatal;
                try appendPaddedDecimal(&out, vm.allocator, parts.day, 2);
            },
            'T' => {
                try appendPaddedDecimal(&out, vm.allocator, parts.hour, 2);
                out.append(vm.allocator, ':') catch return error.Fatal;
                try appendPaddedDecimal(&out, vm.allocator, parts.minute, 2);
                out.append(vm.allocator, ':') catch return error.Fatal;
                try appendPaddedDecimal(&out, vm.allocator, parts.second, 2);
            },
            'Z' => {
                if (t.is_utc) {
                    out.appendSlice(vm.allocator, "UTC") catch return error.Fatal;
                } else {
                    const total_seconds = @divTrunc(t.utc_offset_nanos, nanos_per_second);
                    const sign: u8 = if (total_seconds >= 0) '+' else '-';
                    const abs_seconds = if (total_seconds >= 0) total_seconds else -total_seconds;
                    const off_h = @divTrunc(abs_seconds, seconds_per_hour);
                    const off_m = @divTrunc(@rem(abs_seconds, seconds_per_hour), seconds_per_minute);
                    var buf: [16]u8 = undefined;
                    const s = std.fmt.bufPrint(&buf, "{c}{d:0>2}{d:0>2}", .{ sign, @as(u64, @intCast(off_h)), @as(u64, @intCast(off_m)) }) catch return error.Fatal;
                    out.appendSlice(vm.allocator, s) catch return error.Fatal;
                }
            },
            'a' => {
                const weekday_names = [_][]const u8{ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
                out.appendSlice(vm.allocator, weekday_names[parts.weekday]) catch return error.Fatal;
            },
            'b' => {
                const month_names = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
                out.appendSlice(vm.allocator, month_names[parts.month - 1]) catch return error.Fatal;
            },
            'z' => {
                const total_seconds = if (colon_count >= 2) rounded: {
                    const half_ns = nanos_per_second / 2;
                    break :rounded if (t.utc_offset_nanos >= 0)
                        @divTrunc(t.utc_offset_nanos + half_ns, nanos_per_second)
                    else
                        @divTrunc(t.utc_offset_nanos - half_ns, nanos_per_second);
                } else @divTrunc(t.utc_offset_nanos, nanos_per_second);
                const sign: u8 = if (total_seconds >= 0) if (dash_flag and t.is_utc) '-' else '+' else '-';
                const abs_seconds = if (total_seconds >= 0) total_seconds else -total_seconds;
                const off_h = @divTrunc(abs_seconds, seconds_per_hour);
                const off_m = @divTrunc(@rem(abs_seconds, seconds_per_hour), seconds_per_minute);
                var buf: [32]u8 = undefined;
                const s = if (colon_count >= 2) blk: {
                    const off_s = @rem(abs_seconds, seconds_per_minute);
                    break :blk std.fmt.bufPrint(&buf, "{c}{d:0>2}:{d:0>2}:{d:0>2}", .{ sign, @as(u64, @intCast(off_h)), @as(u64, @intCast(off_m)), @as(u64, @intCast(off_s)) }) catch return error.Fatal;
                } else if (colon_count == 1) blk: {
                    break :blk std.fmt.bufPrint(&buf, "{c}{d:0>2}:{d:0>2}", .{ sign, @as(u64, @intCast(off_h)), @as(u64, @intCast(off_m)) }) catch return error.Fatal;
                } else blk: {
                    break :blk std.fmt.bufPrint(&buf, "{c}{d:0>2}{d:0>2}", .{ sign, @as(u64, @intCast(off_h)), @as(u64, @intCast(off_m)) }) catch return error.Fatal;
                };
                out.appendSlice(vm.allocator, s) catch return error.Fatal;
            },
            'c' => {
                try appendPaddedIntegerValue(&out, vm, parts.year, 4);
                out.append(vm.allocator, '-') catch return error.Fatal;
                try appendPaddedDecimal(&out, vm.allocator, parts.month, 2);
                out.append(vm.allocator, '-') catch return error.Fatal;
                try appendPaddedDecimal(&out, vm.allocator, parts.day, 2);
                out.appendSlice(vm.allocator, " ") catch return error.Fatal;
                try appendPaddedDecimal(&out, vm.allocator, parts.hour, 2);
                out.append(vm.allocator, ':') catch return error.Fatal;
                try appendPaddedDecimal(&out, vm.allocator, parts.minute, 2);
                out.append(vm.allocator, ':') catch return error.Fatal;
                try appendPaddedDecimal(&out, vm.allocator, parts.second, 2);
                out.appendSlice(vm.allocator, " UTC") catch return error.Fatal;
            },
            else => return vm.raiseExceptionFmt(vm.argument_error_class, "unsupported strftime directive", .{}),
        }
    }

    return vm.newString(out.items, false);
}

pub fn builtinTimeNew(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    std.debug.assert(receiver.isClass());
    const class_obj = receiver.toClassObject();
    if (args.len == 0) {
        // Time.new with no args: current local time
        const epoch_nanos = currentEpochNanoseconds();
        const epoch_seconds = floorDiv(epoch_nanos, nanos_per_second);
        const offset_nanos = localUtcOffsetNanos(vm.io, epoch_seconds);
        return vm.newTimeLocal(class_obj, Value.integer(epoch_nanos), offset_nanos);
    }
    if (args.len == 1 and (args[0].isString() or args[0].isSymbol())) {
        const time_string = try args[0].coerceToStringValue(vm, "no implicit conversion into String");
        return vm.newTime(class_obj, try parseTimeString(vm, time_string.toStringObject().str));
    }
    // Time.new(year, month, day, hour, min, sec, utc_offset)
    // Components are wall-clock in the given offset zone.
    const year = try coerceIntegerComponentValue(vm, args[0]);
    const month = if (args.len >= 2 and !args[1].isNil()) try coerceIntegerComponent(vm, args[1]) else 1;
    const day = if (args.len >= 3 and !args[2].isNil()) try coerceIntegerComponent(vm, args[2]) else 1;
    const hour = if (args.len >= 4 and !args[3].isNil()) try coerceIntegerComponent(vm, args[3]) else 0;
    const minute = if (args.len >= 5 and !args[4].isNil()) try coerceIntegerComponent(vm, args[4]) else 0;
    // 6th arg (second) can be Integer, Float, or Rational
    var second: i64 = 0;
    var sec_sub_timew = Value.integer(0);
    if (args.len >= 6 and !args[5].isNil()) {
        const second_exact = try coerceExactNumeric(vm, args[5]);
        const second_whole = try exactFloorDivByInteger(vm, second_exact, 1);
        if ((try vm.compareIntegerValues(second_whole, Value.integer(0))) == .lt or
            (try vm.compareIntegerValues(second_whole, Value.integer(59))) == .gt)
        {
            return vm.raiseExceptionFmt(vm.argument_error_class, "invalid time", .{});
        }
        second = integerToI64(second_whole);
        sec_sub_timew = try exactMul(vm, try exactSub(vm, second_exact, second_whole), Value.integer(nanos_per_second));
    }

    // 7th arg is utc_offset
    var offset_nanos: i64 = 0;
    var has_explicit_offset = false;
    if (args.len >= 7) {
        offset_nanos = try parseUtcOffsetArg(vm, args[6]);
        has_explicit_offset = true;
    } else {
        // No offset provided → local time
        const utc_epoch_nanos = try epochNanosecondsFromUtcComponents(vm, year, month, day, hour, minute, second, 0);
        const utc_epoch_seconds = try epochSecondsForTimezone(vm, utc_epoch_nanos);
        offset_nanos = localUtcOffsetNanos(vm.io, utc_epoch_seconds);
    }

    try validateUtcComponents(vm, year, month, day, hour, minute, second);
    const wall_epoch_nanos = try exactAdd(vm, try epochNanosecondsFromUtcComponents(vm, year, month, day, hour, minute, second, 0), sec_sub_timew);
    const epoch_nanos = try exactSub(vm, wall_epoch_nanos, Value.integer(offset_nanos));
    if (has_explicit_offset) {
        return vm.newTimeWithOffset(class_obj, epoch_nanos, offset_nanos);
    }
    return vm.newTimeLocal(class_obj, epoch_nanos, offset_nanos);
}

pub fn builtinTimeNow(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    std.debug.assert(receiver.isClass());
    const epoch_nanos = currentEpochNanoseconds();
    const epoch_seconds = floorDiv(epoch_nanos, nanos_per_second);
    const offset_nanos = localUtcOffsetNanos(vm.io, epoch_seconds);
    return vm.newTimeLocal(receiver.toClassObject(), Value.integer(epoch_nanos), offset_nanos);
}

pub fn builtinTimeUtc(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    std.debug.assert(receiver.isClass());
    return constructUtcTime(vm, receiver.toClassObject(), args);
}

pub fn builtinTimeLocal(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    std.debug.assert(receiver.isClass());
    return constructLocalTime(vm, receiver.toClassObject(), args);
}

pub fn builtinTimeAt(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    if (args.len < 1 or args.len > 3) {
        try vm.requireArgCountRange(args, 1, 3);
        unreachable;
    }
    std.debug.assert(receiver.isClass());
    const seconds = try coerceExactNumeric(vm, args[0]);
    var timew = try exactMul(vm, seconds, Value.integer(nanos_per_second));
    if (args.len >= 2) {
        const subsecond = try coerceExactNumeric(vm, args[1]);
        const units_per_second: i64 = if (args.len == 2) 1_000_000 else blk: {
            if (!args[2].isSymbol()) {
                return vm.raiseExceptionFmt(vm.argument_error_class, "unexpected unit", .{});
            }
            const unit = args[2].toSymbolObject().name;
            if (std.mem.eql(u8, unit, "nanosecond") or std.mem.eql(u8, unit, "nsec")) break :blk 1_000_000_000;
            if (std.mem.eql(u8, unit, "microsecond") or std.mem.eql(u8, unit, "usec")) break :blk 1_000_000;
            if (std.mem.eql(u8, unit, "millisecond")) break :blk 1_000;
            return vm.raiseExceptionFmt(vm.argument_error_class, "unexpected unit: {s}", .{unit});
        };
        const subsecond_timew = try exactDivByInteger(vm, try exactMul(vm, subsecond, Value.integer(nanos_per_second)), units_per_second);
        timew = try exactAdd(vm, timew, subsecond_timew);
    }
    return vm.newTime(receiver.toClassObject(), timew);
}

pub fn builtinTimeLoad(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    std.debug.assert(receiver.isClass());
    const raw = try args[0].coerceToStr(vm, "no implicit conversion into String");
    const epoch_nanoseconds = (try parseMarshalDumpedUtcNanoseconds(vm, raw)) orelse {
        return vm.raiseExceptionFmt(vm.type_error_class, "marshaled time format differ", .{});
    };
    return vm.newTime(receiver.toClassObject(), epoch_nanoseconds);
}

pub fn builtinTimeUtcInstance(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    if (receiver.toTimeObject().is_utc) return receiver;
    try vm.guardNotFrozen(receiver);
    const t = receiver.toTimeObject();
    t.utc_offset_nanos = 0;
    t.is_utc = true;
    return receiver;
}

pub fn builtinTimeUtcQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.boolean(receiver.toTimeObject().is_utc);
}

pub fn builtinTimeLocaltime(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    if (args.len > 1) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "wrong number of arguments (given {d}, expected 0..1)", .{args.len});
    }
    const t = receiver.toTimeObject();

    if (args.len == 0) {
        // If already in "local" timezone mode (no explicit offset), localtime is a no-op.
        if (t.is_local) return receiver;
        // Convert to system local timezone.
        const epoch_seconds = try epochSecondsForTimezone(vm, t.timew);
        const new_offset = localUtcOffsetNanos(vm.io, epoch_seconds);
        // If already at this exact offset (fixed), do nothing (even if frozen).
        if (!t.is_utc and t.utc_offset_nanos == new_offset) return receiver;
        try vm.guardNotFrozen(receiver);
        t.utc_offset_nanos = new_offset;
        t.is_utc = false;
        t.is_local = true;
        return receiver;
    }

    // With offset argument — first check for utc_to_local protocol.
    const arg = args[0];
    // Check for utc_to_local protocol (timezone object).
    var utc_to_local_args = [_]Value{receiver};
    if (try vm.checkCallMethodByName(arg, "utc_to_local", false, &utc_to_local_args, null)) |result| {
        if (!result.isTime()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "utc_to_local must return a Time", .{});
        }
        const result_t = result.toTimeObject();
        try vm.guardNotFrozen(receiver);
        t.utc_offset_nanos = result_t.utc_offset_nanos;
        t.is_utc = result_t.is_utc;
        return receiver;
    }

    const new_offset = try parseUtcOffsetArg(vm, arg);
    if (!t.is_utc and t.utc_offset_nanos == new_offset) return receiver;
    try vm.guardNotFrozen(receiver);
    t.utc_offset_nanos = new_offset;
    t.is_utc = false;
    return receiver;
}

pub fn builtinTimeUtcOffset(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const t = receiver.toTimeObject();
    const offset_nanos = t.utc_offset_nanos;
    // If evenly divisible by 1_000_000_000, return Integer seconds.
    if (@rem(offset_nanos, nanos_per_second) == 0) {
        return Value.integer(@divTrunc(offset_nanos, nanos_per_second));
    }
    // Otherwise return Rational(offset_nanos, nanos_per_second) reduced.
    return vm.newRational(offset_nanos, nanos_per_second);
}

pub fn builtinTimeYear(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return (try timePartsFor(vm, receiver.toTimeObject())).year;
}

pub fn builtinTimeMonth(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.integer((try timePartsFor(vm, receiver.toTimeObject())).month);
}

pub fn builtinTimeDay(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.integer((try timePartsFor(vm, receiver.toTimeObject())).day);
}

pub fn builtinTimeHour(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.integer((try timePartsFor(vm, receiver.toTimeObject())).hour);
}

pub fn builtinTimeMin(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.integer((try timePartsFor(vm, receiver.toTimeObject())).minute);
}

pub fn builtinTimeSec(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.integer((try timePartsFor(vm, receiver.toTimeObject())).second);
}

pub fn builtinTimeToI(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return exactFloorDivByInteger(vm, receiver.toTimeObject().timew, nanos_per_second);
}

pub fn builtinTimeToF(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return vm.newFloat(exactToF64(receiver.toTimeObject().timew) / @as(f64, @floatFromInt(nanos_per_second)));
}

pub fn builtinTimeToR(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const parts = exactParts(receiver.toTimeObject().timew);
    const denominator = try vm.mulIntegerValues(parts.denominator, Value.integer(nanos_per_second));
    return vm.newRationalValues(parts.numerator, denominator);
}

pub fn builtinTimeNsec(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const timew = receiver.toTimeObject().timew;
    const seconds = try exactFloorDivByInteger(vm, timew, nanos_per_second);
    const whole_seconds_timew = try vm.mulIntegerValues(seconds, Value.integer(nanos_per_second));
    return exactFloorDivByInteger(vm, try exactSub(vm, timew, whole_seconds_timew), 1);
}

pub fn builtinTimeSubsec(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const timew = receiver.toTimeObject().timew;
    const seconds = try exactFloorDivByInteger(vm, timew, nanos_per_second);
    const whole_seconds_timew = try vm.mulIntegerValues(seconds, Value.integer(nanos_per_second));
    return exactDivByInteger(vm, try exactSub(vm, timew, whole_seconds_timew), nanos_per_second);
}

pub fn builtinTimeUsec(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    const nanoseconds = try builtinTimeNsec(vm, receiver, args, block);
    return vm.divFloorIntegerValues(nanoseconds, Value.integer(1000));
}

pub fn builtinTimeToA(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const t = receiver.toTimeObject();
    const parts = try timePartsFor(vm, t);
    const array_obj = try vm.createArray();
    array_obj.elements.append(vm.gc_allocator, Value.integer(parts.second)) catch return error.Fatal;
    array_obj.elements.append(vm.gc_allocator, Value.integer(parts.minute)) catch return error.Fatal;
    array_obj.elements.append(vm.gc_allocator, Value.integer(parts.hour)) catch return error.Fatal;
    array_obj.elements.append(vm.gc_allocator, Value.integer(parts.day)) catch return error.Fatal;
    array_obj.elements.append(vm.gc_allocator, Value.integer(parts.month)) catch return error.Fatal;
    array_obj.elements.append(vm.gc_allocator, parts.year) catch return error.Fatal;
    array_obj.elements.append(vm.gc_allocator, Value.integer(parts.weekday)) catch return error.Fatal;
    array_obj.elements.append(vm.gc_allocator, Value.integer(parts.year_day)) catch return error.Fatal;
    array_obj.elements.append(vm.gc_allocator, Value.boolean(false)) catch return error.Fatal;
    array_obj.elements.append(vm.gc_allocator, try vm.newString(if (t.is_utc) "UTC" else "local", false)) catch return error.Fatal;
    return Value.fromObject(&array_obj.object);
}

pub fn builtinTimePlus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const delta_seconds = try coerceExactNumeric(vm, args[0]);
    const delta_timew = try exactMul(vm, delta_seconds, Value.integer(nanos_per_second));
    const t = receiver.toTimeObject();
    const new_epoch = try exactAdd(vm, t.timew, delta_timew);
    if (t.is_utc) {
        return vm.newTime(t.object.class.?, new_epoch);
    }
    return vm.newTimeWithOffset(t.object.class.?, new_epoch, t.utc_offset_nanos);
}

pub fn builtinTimeMinus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (args[0].isTime()) {
        const diff = try exactSub(vm, receiver.toTimeObject().timew, args[0].toTimeObject().timew);
        return vm.newFloat(exactToF64(diff) / @as(f64, @floatFromInt(nanos_per_second)));
    }
    const delta_seconds = try coerceExactNumeric(vm, args[0]);
    const delta_timew = try exactMul(vm, delta_seconds, Value.integer(nanos_per_second));
    const t = receiver.toTimeObject();
    const new_epoch = try exactSub(vm, t.timew, delta_timew);
    if (t.is_utc) {
        return vm.newTime(t.object.class.?, new_epoch);
    }
    return vm.newTimeWithOffset(t.object.class.?, new_epoch, t.utc_offset_nanos);
}

pub fn builtinTimeCompare(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (!args[0].isTime()) return Value.nil();
    return Value.integer(switch (try exactCompare(vm, receiver.toTimeObject().timew, args[0].toTimeObject().timew)) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    });
}

pub fn builtinTimeStrftime(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const format_value = try args[0].coerceToStringValue(vm, "no implicit conversion into String");
    return buildStrftimeValue(vm, receiver, format_value.toStringObject().str);
}

pub fn builtinTimeToS(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return timeStringValue(vm, receiver);
}

pub fn builtinTimeInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return timeStringValue(vm, receiver);
}

pub fn builtinTimeHash(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const hash_value: i64 = @bitCast(receiver.hash());
    return Value.integer(hash_value);
}

pub fn builtinTimeEql(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (!args[0].isTime()) return Value.boolean(false);
    return Value.boolean((try exactCompare(vm, receiver.toTimeObject().timew, args[0].toTimeObject().timew)) == .eq);
}

pub fn builtinTimeZone(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const t = receiver.toTimeObject();
    if (t.is_utc) {
        return vm.newString("UTC", false);
    }
    // For fixed-offset times, Ruby returns a string like "+01:00".
    const total_seconds = @divTrunc(t.utc_offset_nanos, nanos_per_second);
    const sign: u8 = if (total_seconds >= 0) '+' else '-';
    const abs_seconds = if (total_seconds >= 0) total_seconds else -total_seconds;
    const off_h = @divTrunc(abs_seconds, seconds_per_hour);
    const off_m = @divTrunc(@rem(abs_seconds, seconds_per_hour), seconds_per_minute);
    var buf: [16]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{c}{d:0>2}:{d:0>2}", .{ sign, @as(u64, @intCast(off_h)), @as(u64, @intCast(off_m)) }) catch return error.Fatal;
    return vm.newString(s, false);
}
