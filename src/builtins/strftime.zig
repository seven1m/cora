const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Value = value.Value;

const nanos_per_second: i64 = 1_000_000_000;
const seconds_per_minute: i64 = 60;
const seconds_per_hour: i64 = 3_600;

pub const Parts = struct {
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

pub const Zone = struct {
    utc_offset_nanos: i64,
    is_utc: bool,
    name_style: NameStyle = .time,
};

pub const NameStyle = enum {
    time,
    offset,
};

pub fn appendPaddedDecimal(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value_in: anytype, width: usize) VMError!void {
    const value_i64: i64 = @intCast(value_in);
    var buffer: [32]u8 = undefined;
    const digits = std.fmt.bufPrint(&buffer, "{d}", .{value_i64}) catch return error.Fatal;
    if (digits.len < width) {
        for (0..width - digits.len) |_| out.append(allocator, '0') catch return error.Fatal;
    }
    out.appendSlice(allocator, digits) catch return error.Fatal;
}

pub fn appendPaddedIntegerValue(out: *std.ArrayList(u8), vm: *VM, integer: Value, width: usize) VMError!void {
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
    for (0..width - 9) |_| out.append(allocator, '0') catch return error.Fatal;
}

pub fn build(vm: *VM, parts: Parts, zone: Zone, format_bytes: []const u8) VMError!Value {
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
        if (index >= format_bytes.len) return vm.raiseExceptionFmt(vm.argument_error_class, "incomplete strftime directive", .{});

        var dash_flag = false;
        while (index < format_bytes.len) : (index += 1) {
            switch (format_bytes[index]) {
                '-' => dash_flag = true,
                '0', '_' => {},
                else => break,
            }
        }

        var colon_count: usize = 0;
        while (index < format_bytes.len and format_bytes[index] == ':') : (index += 1) colon_count += 1;

        var width: usize = 0;
        var saw_width = false;
        while (index < format_bytes.len and std.ascii.isDigit(format_bytes[index])) : (index += 1) {
            saw_width = true;
            width = width * 10 + (format_bytes[index] - '0');
        }
        if (index >= format_bytes.len) return vm.raiseExceptionFmt(vm.argument_error_class, "incomplete strftime directive", .{});

        const directive = format_bytes[index];
        index += 1;
        switch (directive) {
            '%' => out.append(vm.allocator, '%') catch return error.Fatal,
            'Y' => try appendPaddedIntegerValue(&out, vm, parts.year, 4),
            'm' => try appendPaddedDecimal(&out, vm.allocator, parts.month, 2),
            'd' => try appendPaddedDecimal(&out, vm.allocator, parts.day, 2),
            'e' => {
                if (parts.day < 10) out.append(vm.allocator, ' ') catch return error.Fatal;
                try appendPaddedDecimal(&out, vm.allocator, parts.day, 1);
            },
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
                if (zone.name_style == .time and zone.is_utc) {
                    out.appendSlice(vm.allocator, "UTC") catch return error.Fatal;
                } else {
                    const total_seconds = @divTrunc(zone.utc_offset_nanos, nanos_per_second);
                    const sign: u8 = if (total_seconds >= 0) '+' else '-';
                    const abs_seconds = if (total_seconds >= 0) total_seconds else -total_seconds;
                    const off_h = @divTrunc(abs_seconds, seconds_per_hour);
                    const off_m = @divTrunc(@rem(abs_seconds, seconds_per_hour), seconds_per_minute);
                    var buf: [16]u8 = undefined;
                    const text = if (zone.name_style == .offset)
                        std.fmt.bufPrint(&buf, "{c}{d:0>2}:{d:0>2}", .{ sign, @as(u64, @intCast(off_h)), @as(u64, @intCast(off_m)) }) catch return error.Fatal
                    else
                        std.fmt.bufPrint(&buf, "{c}{d:0>2}{d:0>2}", .{ sign, @as(u64, @intCast(off_h)), @as(u64, @intCast(off_m)) }) catch return error.Fatal;
                    out.appendSlice(vm.allocator, text) catch return error.Fatal;
                }
            },
            'a' => {
                const names = [_][]const u8{ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
                out.appendSlice(vm.allocator, names[parts.weekday]) catch return error.Fatal;
            },
            'b' => {
                const names = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
                out.appendSlice(vm.allocator, names[parts.month - 1]) catch return error.Fatal;
            },
            'z' => {
                const total_seconds = if (colon_count >= 2) rounded: {
                    const half_ns = nanos_per_second / 2;
                    break :rounded if (zone.utc_offset_nanos >= 0)
                        @divTrunc(zone.utc_offset_nanos + half_ns, nanos_per_second)
                    else
                        @divTrunc(zone.utc_offset_nanos - half_ns, nanos_per_second);
                } else @divTrunc(zone.utc_offset_nanos, nanos_per_second);
                const sign: u8 = if (total_seconds >= 0) if (dash_flag and zone.is_utc) '-' else '+' else '-';
                const abs_seconds = if (total_seconds >= 0) total_seconds else -total_seconds;
                const off_h = @divTrunc(abs_seconds, seconds_per_hour);
                const off_m = @divTrunc(@rem(abs_seconds, seconds_per_hour), seconds_per_minute);
                var buf: [32]u8 = undefined;
                const text = if (colon_count >= 2) blk: {
                    const off_s = @rem(abs_seconds, seconds_per_minute);
                    break :blk std.fmt.bufPrint(&buf, "{c}{d:0>2}:{d:0>2}:{d:0>2}", .{ sign, @as(u64, @intCast(off_h)), @as(u64, @intCast(off_m)), @as(u64, @intCast(off_s)) }) catch return error.Fatal;
                } else if (colon_count == 1)
                    std.fmt.bufPrint(&buf, "{c}{d:0>2}:{d:0>2}", .{ sign, @as(u64, @intCast(off_h)), @as(u64, @intCast(off_m)) }) catch return error.Fatal
                else
                    std.fmt.bufPrint(&buf, "{c}{d:0>2}{d:0>2}", .{ sign, @as(u64, @intCast(off_h)), @as(u64, @intCast(off_m)) }) catch return error.Fatal;
                out.appendSlice(vm.allocator, text) catch return error.Fatal;
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
