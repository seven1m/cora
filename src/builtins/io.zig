const std = @import("std");
const enc = @import("../encoding.zig");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;
const IoObject = value.IoObject;

extern "c" fn clock_gettime(clk_id: std.posix.CLOCK, tp: *std.posix.timespec) c_int;

fn monotonicMilliseconds() i64 {
    var timespec: std.posix.timespec = undefined;
    if (clock_gettime(std.posix.CLOCK.MONOTONIC, &timespec) != 0) return 0;

    const seconds: i64 = @intCast(timespec.sec);
    const nanoseconds: i64 = @intCast(timespec.nsec);
    return seconds * 1_000 + @divTrunc(nanoseconds, 1_000_000);
}

pub fn register(vm: *VM) !void {
    const io_class_val = Value.fromObject(&vm.io_class.module.object);
    const io_singleton = try vm.getOrCreateSingletonClass(io_class_val);

    const pipe_sym = try vm.intern("pipe");
    try io_singleton.module.methods.put(pipe_sym, value.MethodEntry.builtin(&builtinIoPipe, .{ .exact = 0 }));

    const to_io_sym = try vm.intern("to_io");
    try vm.io_class.module.methods.put(to_io_sym, value.MethodEntry.builtin(&builtinIoToIo, .{ .exact = 0 }));

    const nonblock_q_sym = try vm.intern("nonblock?");
    try vm.io_class.module.methods.put(nonblock_q_sym, value.MethodEntry.builtin(&builtinIoNonblockQ, .{ .exact = 0 }));

    const nonblock_set_sym = try vm.intern("nonblock=");
    try vm.io_class.module.methods.put(nonblock_set_sym, value.MethodEntry.builtin(&builtinIoNonblockSet, .{ .exact = 1 }));

    const nonblock_sym = try vm.intern("nonblock");
    try vm.io_class.module.methods.put(nonblock_sym, value.MethodEntry.builtin(&builtinIoNonblock, .{ .variadic = 0 }));

    const read_sym = try vm.intern("read");
    try vm.io_class.module.methods.put(read_sym, value.MethodEntry.builtin(&builtinIoRead, .{ .variadic = 0 }));

    const read_nonblock_sym = try vm.intern("read_nonblock");
    try vm.io_class.module.methods.put(read_nonblock_sym, value.MethodEntry.builtin(&builtinIoReadNonblock, .{ .variadic = 1 }));

    const write_sym = try vm.intern("write");
    try vm.io_class.module.methods.put(write_sym, value.MethodEntry.builtin(&builtinIoWrite, .{ .variadic = 0 }));

    const append_sym = try vm.intern("<<");
    try vm.io_class.module.methods.put(append_sym, value.MethodEntry.builtin(&builtinIoAppend, .{ .exact = 1 }));

    const write_nonblock_sym = try vm.intern("write_nonblock");
    try vm.io_class.module.methods.put(write_nonblock_sym, value.MethodEntry.builtin(&builtinIoWriteNonblock, .{ .exact = 1 }));

    const print_sym = try vm.intern("print");
    try vm.io_class.module.methods.put(print_sym, value.MethodEntry.builtin(&builtinIoPrint, .{ .variadic = 0 }));

    const puts_sym = try vm.intern("puts");
    try vm.io_class.module.methods.put(puts_sym, value.MethodEntry.builtin(&builtinIoPuts, .{ .variadic = 0 }));

    const flush_sym = try vm.intern("flush");
    try vm.io_class.module.methods.put(flush_sym, value.MethodEntry.builtin(&builtinIoFlush, .{ .exact = 0 }));

    const close_sym = try vm.intern("close");
    try vm.io_class.module.methods.put(close_sym, value.MethodEntry.builtin(&builtinIoClose, .{ .exact = 0 }));

    const closed_sym = try vm.intern("closed?");
    try vm.io_class.module.methods.put(closed_sym, value.MethodEntry.builtin(&builtinIoClosed, .{ .exact = 0 }));

    const eof_sym = try vm.intern("eof");
    try vm.io_class.module.methods.put(eof_sym, value.MethodEntry.builtin(&builtinIoEof, .{ .exact = 0 }));

    const eof_q_sym = try vm.intern("eof?");
    try vm.io_class.module.methods.put(eof_q_sym, value.MethodEntry.builtin(&builtinIoEof, .{ .exact = 0 }));

    const fileno_sym = try vm.intern("fileno");
    try vm.io_class.module.methods.put(fileno_sym, value.MethodEntry.builtin(&builtinIoFileno, .{ .exact = 0 }));

    const gets_sym = try vm.intern("gets");
    try vm.io_class.module.methods.put(gets_sym, value.MethodEntry.builtin(&builtinIoGets, .{ .variadic = 0 }));

    const each_sym = try vm.intern("each");
    try vm.io_class.module.methods.put(each_sym, value.MethodEntry.builtin(&builtinIoEach, .{ .exact = 0 }));

    const each_line_sym = try vm.intern("each_line");
    try vm.io_class.module.methods.put(each_line_sym, value.MethodEntry.builtin(&builtinIoEach, .{ .exact = 0 }));

    const nread_sym = try vm.intern("nread");
    try vm.io_class.module.methods.put(nread_sym, value.MethodEntry.builtin(&builtinIoNread, .{ .exact = 0 }));

    const ready_q_sym = try vm.intern("ready?");
    try vm.io_class.module.methods.put(ready_q_sym, value.MethodEntry.builtin(&builtinIoReady, .{ .exact = 0 }));

    const wait_readable_sym = try vm.intern("wait_readable");
    try vm.io_class.module.methods.put(wait_readable_sym, value.MethodEntry.builtin(&builtinIoWaitReadable, .{ .variadic = 0 }));

    const wait_writable_sym = try vm.intern("wait_writable");
    try vm.io_class.module.methods.put(wait_writable_sym, value.MethodEntry.builtin(&builtinIoWaitWritable, .{ .variadic = 0 }));
}

pub fn builtinIoPipe(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const io_class = if (receiver.isClass()) receiver.toClassObject() else vm.io_class;

    var fds: [2]std.c.fd_t = undefined;
    if (std.c.pipe(&fds) != 0) {
        return vm.raiseErrnoFmt(std.posix.errno(-1), "pipe failed", .{});
    }
    errdefer {
        _ = std.c.close(fds[0]);
        _ = std.c.close(fds[1]);
    }

    const read_io = try vm.newIo(io_class, @intCast(fds[0]), true, true, false, false, null);
    const write_io = try vm.newIo(io_class, @intCast(fds[1]), true, false, true, false, null);
    try ensureIoNonblocking(vm, read_io.toIoObject());
    try ensureIoNonblocking(vm, write_io.toIoObject());

    const pair = try vm.createArray();
    pair.elements.append(vm.gc_allocator, read_io) catch return error.Fatal;
    pair.elements.append(vm.gc_allocator, write_io) catch return error.Fatal;
    return Value.fromObject(&pair.object);
}

pub fn builtinIoToIo(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    _ = try requireIoReceiver(vm, receiver);
    return receiver;
}

pub fn builtinIoNonblockQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const io = try requireIoReceiver(vm, receiver);
    try ensureIoOpen(vm, io);
    return Value.boolean(try ioIsNonblocking(vm, io));
}

pub fn builtinIoNonblockSet(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const io = try requireIoReceiver(vm, receiver);
    try ensureIoOpen(vm, io);
    try setIoNonblocking(vm, io, args[0].is_truthy());
    return receiver;
}

pub fn builtinIoNonblock(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const io = try requireIoReceiver(vm, receiver);
    try ensureIoOpen(vm, io);

    const blk = try vm.requireBlock(block);
    const desired = if (args.len == 0) true else args[0].is_truthy();
    const original = try ioIsNonblocking(vm, io);

    if (original == desired) {
        const yielded = try vm.yieldToBlock(blk, &[_]Value{receiver});
        if (yielded.controlFlowValue()) |return_value| return return_value;
        return yielded.value;
    }

    try setIoNonblocking(vm, io, desired);
    const yielded = vm.yieldToBlock(blk, &[_]Value{receiver}) catch |err| {
        try setIoNonblocking(vm, io, original);
        return err;
    };
    try setIoNonblocking(vm, io, original);
    if (yielded.controlFlowValue()) |return_value| return return_value;
    return yielded.value;
}

pub fn builtinIoGets(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const io = try requireIoReceiver(vm, receiver);
    try ensureIoReadable(vm, io);

    const fd: std.posix.fd_t = @intCast(io.fd);
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.allocator);

    var byte: [1]u8 = undefined;
    while (true) {
        const n = std.posix.read(fd, &byte) catch return vm.raiseExceptionFmt(vm.io_error_class, "read failed", .{});
        if (n == 0) {
            if (out.items.len == 0) return Value.nil();
            break;
        }
        out.append(vm.allocator, byte[0]) catch return error.Fatal;
        if (byte[0] == '\n') break;
    }
    return vm.newString(out.items, false);
}

pub fn builtinIoEach(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        return vm.createMethodEnumerator(receiver, try vm.intern("each"), &.{});
    };

    var empty_args = [_]Value{};
    while (true) {
        const line = try builtinIoGets(vm, receiver, empty_args[0..], null);
        if (line.isNil()) break;
        const yield_args = [_]Value{line};
        const result = try vm.yieldToBlock(blk, &yield_args);
        if (result.controlFlowValue()) |return_value| return return_value;
    }

    return receiver;
}

fn requireIoReceiver(vm: *VM, receiver: Value) VMError!*IoObject {
    if (receiver.isIo()) return receiver.toIoObject();
    return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not an IO", .{});
}

fn ensureIoOpen(vm: *VM, io: *IoObject) VMError!void {
    if (io.closed) {
        return vm.raiseExceptionFmt(vm.io_error_class, "closed stream", .{});
    }
}

fn ensureIoReadable(vm: *VM, io: *IoObject) VMError!void {
    try ensureIoOpen(vm, io);
    if (!io.readable) {
        return vm.raiseExceptionFmt(vm.io_error_class, "not opened for reading", .{});
    }
}

fn ensureIoWritable(vm: *VM, io: *IoObject) VMError!void {
    try ensureIoOpen(vm, io);
    if (!io.writable) {
        return vm.raiseExceptionFmt(vm.io_error_class, "not opened for writing", .{});
    }
}

fn timeoutArgToSeconds(vm: *VM, timeout: Value) VMError!?f64 {
    if (timeout.isNil()) return null;
    if (timeout.isInteger()) return timeout.integerToF64();
    if (timeout.isFloat()) return timeout.toFloatObject().val;
    return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into time interval", .{vm.className(timeout)});
}

fn timeoutArgToPollMilliseconds(vm: *VM, timeout: Value) VMError!i32 {
    const seconds = (try timeoutArgToSeconds(vm, timeout)) orelse return -1;
    if (seconds < 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "time interval must not be negative", .{});
    }

    const max_ms = @as(f64, @floatFromInt(std.math.maxInt(i32)));
    const ms = seconds * 1000.0;
    if (ms >= max_ms) return std.math.maxInt(i32);
    return @intFromFloat(@floor(ms));
}

fn waitForIo(vm: *VM, io: *IoObject, events: i16, timeout_ms: i32, include_hup: bool) VMError!bool {
    var fds = [_]std.posix.pollfd{.{
        .fd = @intCast(io.fd),
        .events = events,
        .revents = 0,
    }};
    const ready_mask = blk: {
        var mask = events | std.posix.POLL.ERR;
        if (include_hup) mask |= std.posix.POLL.HUP;
        break :blk mask;
    };

    const current_thread = vm.current_thread;
    const is_worker_thread = current_thread != null and vm.main_thread != null and current_thread.? != vm.main_thread.?;
    if (!is_worker_thread) {
        const ready_count = std.posix.poll(fds[0..], timeout_ms) catch return vm.raiseExceptionFmt(vm.io_error_class, "poll failed", .{});
        if (ready_count == 0) return false;
        return (fds[0].revents & ready_mask) != 0;
    }

    const thread = current_thread.?;
    const deadline_ms = if (timeout_ms < 0) null else monotonicMilliseconds() + timeout_ms;
    defer {
        thread.io_wait = null;
        if (thread.state == .sleeping) thread.state = .running;
    }

    while (true) {
        const ready_count = std.posix.poll(fds[0..], 0) catch return vm.raiseExceptionFmt(vm.io_error_class, "poll failed", .{});
        if (ready_count != 0) {
            return (fds[0].revents & ready_mask) != 0;
        }

        if (deadline_ms) |deadline| {
            if (monotonicMilliseconds() >= deadline) return false;
        }

        thread.io_wait = .{
            .fd = io.fd,
            .events = events,
            .include_hup = include_hup,
            .deadline_ms = deadline_ms,
        };
        thread.state = .sleeping;
        try vm.threadYield();
    }
}

fn waitReadable(vm: *VM, io: *IoObject, timeout_ms: i32) VMError!bool {
    return waitForIo(vm, io, std.posix.POLL.IN, timeout_ms, true);
}

fn waitWritable(vm: *VM, io: *IoObject, timeout_ms: i32) VMError!bool {
    return waitForIo(vm, io, std.posix.POLL.OUT, timeout_ms, false);
}

fn maybeRemainingSeekableBytes(io: *IoObject) ?usize {
    const fd: std.posix.fd_t = @intCast(io.fd);
    const cur = std.c.lseek(fd, 0, std.posix.SEEK.CUR);
    if (cur < 0) return null;

    const end = std.c.lseek(fd, 0, std.posix.SEEK.END);
    if (end < 0) {
        _ = std.c.lseek(fd, cur, std.posix.SEEK.SET);
        return null;
    }

    _ = std.c.lseek(fd, cur, std.posix.SEEK.SET);
    if (end <= cur) return 0;
    return @intCast(end - cur);
}

fn pendingIoBytes(io: *IoObject) usize {
    if (maybeRemainingSeekableBytes(io)) |remaining| return remaining;

    var bytes_available: c_int = 0;
    const fd: std.posix.fd_t = @intCast(io.fd);
    if (std.c.ioctl(fd, std.c.T.FIONREAD, &bytes_available) == 0 and bytes_available > 0) {
        return @intCast(bytes_available);
    }
    return 0;
}

fn ioOutBufferValue(vm: *VM, maybe_outbuf: ?Value, bytes: []const u8) VMError!Value {
    if (maybe_outbuf) |outbuf| {
        const string_obj = outbuf.toStringObject();
        const copy = vm.gc_allocator_atomic.dupe(u8, bytes) catch return error.Fatal;
        string_obj.str = copy;
        string_obj.validity = .unknown;
        return outbuf;
    }

    return vm.newStringWithEncoding(bytes, false, enc.Encoding{ .ascii_8bit = .{} });
}

fn exceptionKeywordEnabled(vm: *VM) VMError!bool {
    var exception_value: ?Value = null;
    try vm.consumeKeywordArgs(.{"exception"}, .{&exception_value});
    try vm.validateKeywordArgsConsumed();

    const raw = exception_value orelse return true;
    if (raw.isTrue()) return true;
    if (raw.isFalse()) return false;
    return vm.raiseExceptionFmt(vm.type_error_class, "expected true or false as exception", .{});
}

fn ioStatusFlags(vm: *VM, io: *IoObject) VMError!c_int {
    const fd: std.posix.fd_t = @intCast(io.fd);
    const flags = std.c.fcntl(fd, std.c.F.GETFL, @as(c_int, 0));
    if (flags < 0) {
        return vm.raiseErrnoFmt(std.posix.errno(-1), "fcntl failed", .{});
    }
    return flags;
}

fn setIoNonblocking(vm: *VM, io: *IoObject, enabled: bool) VMError!void {
    const flags = try ioStatusFlags(vm, io);
    const nonblock_flag: c_int = @intCast(std.c.SOCK.NONBLOCK);
    const already_enabled = (flags & nonblock_flag) != 0;
    if (already_enabled == enabled) return;

    const next_flags = if (enabled) flags | nonblock_flag else flags & ~nonblock_flag;
    const fd: std.posix.fd_t = @intCast(io.fd);
    if (std.c.fcntl(fd, std.c.F.SETFL, next_flags) < 0) {
        return vm.raiseErrnoFmt(std.posix.errno(-1), "fcntl failed", .{});
    }
}

fn ensureIoNonblocking(vm: *VM, io: *IoObject) VMError!void {
    return setIoNonblocking(vm, io, true);
}

fn ioIsNonblocking(vm: *VM, io: *IoObject) VMError!bool {
    const flags = try ioStatusFlags(vm, io);
    const nonblock_flag: c_int = @intCast(std.c.SOCK.NONBLOCK);
    return (flags & nonblock_flag) != 0;
}

fn ioWriteBytes(vm: *VM, io: *IoObject, bytes: []const u8) VMError!usize {
    try ensureIoWritable(vm, io);

    if (io.fd == 1) {
        vm.setupOutput();
        vm.stdout.?.writeAll(bytes) catch return vm.raiseExceptionFmt(vm.io_error_class, "write failed", .{});
        return bytes.len;
    }
    if (io.fd == 2) {
        vm.setupOutput();
        vm.stderr.?.writeAll(bytes) catch return vm.raiseExceptionFmt(vm.io_error_class, "write failed", .{});
        return bytes.len;
    }

    const fd: std.posix.fd_t = @intCast(io.fd);
    var total: usize = 0;
    while (total < bytes.len) {
        const n = std.c.write(fd, bytes[total..].ptr, bytes[total..].len);
        if (n < 0) return vm.raiseExceptionFmt(vm.io_error_class, "write failed", .{});
        if (n == 0) break;
        total += @intCast(n);
    }
    return total;
}

fn ioReadAll(vm: *VM, io: *IoObject) VMError!Value {
    try ensureIoReadable(vm, io);
    const fd: std.posix.fd_t = @intCast(io.fd);
    var buf: [4096]u8 = undefined;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.allocator);

    while (true) {
        const n = std.posix.read(fd, &buf) catch return vm.raiseExceptionFmt(vm.io_error_class, "read failed", .{});
        if (n == 0) break;
        out.appendSlice(vm.allocator, buf[0..n]) catch return error.Fatal;
    }

    return vm.newString(out.items, false);
}

fn ioReadN(vm: *VM, io: *IoObject, len: usize) VMError!Value {
    try ensureIoReadable(vm, io);
    if (len == 0) return vm.newString("", false);

    const fd: std.posix.fd_t = @intCast(io.fd);
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.allocator);
    out.ensureTotalCapacity(vm.allocator, len) catch return error.Fatal;

    var remaining = len;
    var buf: [4096]u8 = undefined;
    while (remaining > 0) {
        const to_read = @min(remaining, buf.len);
        const n = std.posix.read(fd, buf[0..to_read]) catch return vm.raiseExceptionFmt(vm.io_error_class, "read failed", .{});
        if (n == 0) break;
        out.appendSlice(vm.allocator, buf[0..n]) catch return error.Fatal;
        remaining -= n;
    }

    if (out.items.len == 0) return Value.nil();
    return vm.newString(out.items, false);
}

pub fn builtinIoRead(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const io = try requireIoReceiver(vm, receiver);

    if (args.len == 0 or args[0].isNil()) {
        return ioReadAll(vm, io);
    }

    if (!args[0].isInteger()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into Integer", .{});
    }
    if (args[0].toInteger() < 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "negative length {d} given", .{args[0].toInteger()});
    }

    return ioReadN(vm, io, @intCast(args[0].toInteger()));
}

pub fn builtinIoReadNonblock(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    const io = try requireIoReceiver(vm, receiver);
    try ensureIoReadable(vm, io);

    const exception_enabled = try exceptionKeywordEnabled(vm);
    const len = try args[0].integerArgToI64(vm, "no implicit conversion into Integer", "integer too big to convert into `long`");
    if (len < 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "negative length {d} given", .{len});
    }

    const outbuf = if (args.len == 2)
        try args[1].coerceToStringValue(vm, "no implicit conversion into String")
    else
        null;

    if (len == 0) return ioOutBufferValue(vm, outbuf, "");
    try ensureIoNonblocking(vm, io);

    if (!try waitReadable(vm, io, 0)) {
        if (!exception_enabled) return Value.fromObject(&(try vm.intern("wait_readable")).object);
        return vm.raiseExceptionFmt(vm.io_eagain_wait_readable_class, "read would block", .{});
    }

    const fd: std.posix.fd_t = @intCast(io.fd);
    const buf = vm.allocator.alloc(u8, @intCast(len)) catch return error.Fatal;
    defer vm.allocator.free(buf);

    const read_len = std.c.read(fd, buf.ptr, buf.len);
    if (read_len < 0) {
        const errno_code = std.posix.errno(read_len);
        if (errno_code == .AGAIN) {
            if (!exception_enabled) return Value.fromObject(&(try vm.intern("wait_readable")).object);
            return vm.raiseExceptionFmt(vm.io_eagain_wait_readable_class, "read would block", .{});
        }
        return vm.raiseErrnoFmt(errno_code, "read failed", .{});
    }

    if (read_len == 0) {
        if (!exception_enabled) return Value.nil();
        if (outbuf) |buffer| {
            _ = try ioOutBufferValue(vm, buffer, "");
        }
        return vm.raiseExceptionFmt(vm.eof_error_class, "end of file reached", .{});
    }

    return ioOutBufferValue(vm, outbuf, buf[0..@intCast(read_len)]);
}

pub fn builtinIoWrite(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const io = try requireIoReceiver(vm, receiver);
    const str = try args[0].coerceToStr(vm, "no implicit conversion into String");
    const written = try ioWriteBytes(vm, io, str);
    return Value.integer(@intCast(written));
}

pub fn builtinIoAppend(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const io = try requireIoReceiver(vm, receiver);
    const str = try args[0].coerceToStr(vm, "no implicit conversion into String");
    _ = try ioWriteBytes(vm, io, str);
    return receiver;
}

pub fn builtinIoWriteNonblock(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const io = try requireIoReceiver(vm, receiver);
    try ensureIoWritable(vm, io);

    const exception_enabled = try exceptionKeywordEnabled(vm);
    const str_val = try vm.callMethodByName(args[0], "to_s", &[_]Value{}, null);
    if (!str_val.isString()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "to_s did not return String", .{});
    }
    const str = str_val.toStringObject().str;
    if (str.len == 0) return Value.integer(0);
    try ensureIoNonblocking(vm, io);

    if (!try waitWritable(vm, io, 0)) {
        if (!exception_enabled) return Value.fromObject(&(try vm.intern("wait_writable")).object);
        return vm.raiseExceptionFmt(vm.io_eagain_wait_writable_class, "write would block", .{});
    }

    const fd: std.posix.fd_t = @intCast(io.fd);
    const written = std.c.write(fd, str.ptr, str.len);
    if (written < 0) {
        const errno_code = std.posix.errno(written);
        if (errno_code == .AGAIN) {
            if (!exception_enabled) return Value.fromObject(&(try vm.intern("wait_writable")).object);
            return vm.raiseExceptionFmt(vm.io_eagain_wait_writable_class, "write would block", .{});
        }
        if (errno_code == .PIPE) {
            return vm.raiseErrnoFmt(errno_code, "Broken pipe", .{});
        }
        return vm.raiseErrnoFmt(errno_code, "write failed", .{});
    }

    return Value.integer(@intCast(written));
}

pub fn builtinIoPrint(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const io = try requireIoReceiver(vm, receiver);
    for (args) |arg| {
        const str_val = try vm.callMethodByName(arg, "to_s", &[_]Value{}, null);
        if (!str_val.isString()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "to_s did not return String", .{});
        }
        _ = try ioWriteBytes(vm, io, str_val.toStringObject().str);
    }
    return Value.nil();
}

pub fn builtinIoPuts(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const io = try requireIoReceiver(vm, receiver);
    if (args.len == 0) {
        _ = try ioWriteBytes(vm, io, "\n");
        _ = try builtinIoFlush(vm, receiver, &[_]Value{}, null);
        return Value.nil();
    }

    for (args) |arg| {
        try ioPutsValue(vm, io, arg);
    }
    _ = try builtinIoFlush(vm, receiver, &[_]Value{}, null);
    return Value.nil();
}

fn ioPutsValue(vm: *VM, io: *IoObject, arg: Value) VMError!void {
    if (arg.isArray()) {
        for (arg.toArrayObject().elements.items) |elem| {
            try ioPutsValue(vm, io, elem);
        }
        return;
    }

    const str_val = try vm.callMethodByName(arg, "to_s", &[_]Value{}, null);
    if (!str_val.isString()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "to_s did not return String", .{});
    }
    const str = str_val.toStringObject().str;
    _ = try ioWriteBytes(vm, io, str);
    if (!std.mem.endsWith(u8, str, "\n")) {
        _ = try ioWriteBytes(vm, io, "\n");
    }
}

pub fn builtinIoFlush(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const io = try requireIoReceiver(vm, receiver);
    try ensureIoOpen(vm, io);
    if (io.fd == 1) {
        vm.setupOutput();
        _ = vm.stdout.?.flush() catch {};
    } else if (io.fd == 2) {
        vm.setupOutput();
        _ = vm.stderr.?.flush() catch {};
    }
    return receiver;
}

pub fn builtinIoClose(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const io = try requireIoReceiver(vm, receiver);
    if (io.closed) return Value.nil();

    if (io.owns_fd and io.fd >= 0) {
        _ = std.c.close(@intCast(io.fd));
    }
    io.closed = true;
    return Value.nil();
}

pub fn builtinIoEof(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const io = try requireIoReceiver(vm, receiver);
    try ensureIoReadable(vm, io);

    if (maybeRemainingSeekableBytes(io)) |remaining| {
        return Value.boolean(remaining == 0);
    }

    if (!try waitReadable(vm, io, 0)) return Value.boolean(false);
    return Value.boolean(pendingIoBytes(io) == 0);
}

pub fn builtinIoClosed(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const io = try requireIoReceiver(vm, receiver);
    return Value.boolean(io.closed);
}

pub fn builtinIoFileno(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const io = try requireIoReceiver(vm, receiver);
    return Value.integer(io.fd);
}

pub fn builtinIoNread(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const io = try requireIoReceiver(vm, receiver);
    try ensureIoReadable(vm, io);
    return Value.integer(@intCast(pendingIoBytes(io)));
}

pub fn builtinIoReady(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const io = try requireIoReceiver(vm, receiver);
    try ensureIoReadable(vm, io);

    if (pendingIoBytes(io) > 0) return Value.boolean(true);
    return Value.boolean(try waitReadable(vm, io, 0));
}

pub fn builtinIoWaitReadable(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const io = try requireIoReceiver(vm, receiver);
    try ensureIoReadable(vm, io);

    const timeout_ms = if (args.len == 1) try timeoutArgToPollMilliseconds(vm, args[0]) else -1;
    if (pendingIoBytes(io) > 0) return receiver;
    return if (try waitReadable(vm, io, timeout_ms)) receiver else Value.nil();
}

pub fn builtinIoWaitWritable(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const io = try requireIoReceiver(vm, receiver);
    try ensureIoWritable(vm, io);

    const timeout_ms = if (args.len == 1) try timeoutArgToPollMilliseconds(vm, args[0]) else -1;
    return if (try waitWritable(vm, io, timeout_ms)) receiver else Value.nil();
}
