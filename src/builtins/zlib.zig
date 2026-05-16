const std = @import("std");
const enc = @import("../encoding.zig");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;
const ClassObject = value.ClassObject;

const binary_encoding = enc.Encoding{ .ascii_8bit = .{} };

const ContainerKind = enum(i64) {
    raw = 0,
    gzip = 1,
    zlib = 2,
    auto = 3,
};

pub fn register(vm: *VM) !void {
    const zlib_name = try vm.intern("Zlib");
    if (vm.object_class.module.constants.contains(zlib_name)) return;

    const zlib_val = try vm.newModule(zlib_name);
    const zlib_mod = zlib_val.toModuleObject();
    try vm.object_class.module.constants.put(zlib_name, .{ .value = zlib_val });

    const error_name = try vm.intern("Error");
    const error_val = try vm.newClass(error_name, vm.standard_error_class);
    try zlib_mod.constants.put(error_name, .{ .value = error_val });

    const data_error_name = try vm.intern("DataError");
    const data_error_val = try vm.newClass(data_error_name, error_val.toClassObject());
    try zlib_mod.constants.put(data_error_name, .{ .value = data_error_val });

    const stream_error_name = try vm.intern("StreamError");
    const stream_error_val = try vm.newClass(stream_error_name, error_val.toClassObject());
    try zlib_mod.constants.put(stream_error_name, .{ .value = stream_error_val });

    const buf_error_name = try vm.intern("BufError");
    const buf_error_val = try vm.newClass(buf_error_name, error_val.toClassObject());
    try zlib_mod.constants.put(buf_error_name, .{ .value = buf_error_val });

    const gzip_file_name = try vm.intern("GzipFile");
    const gzip_file_val = try vm.newClass(gzip_file_name, vm.object_class);
    const gzip_file_class = gzip_file_val.toClassObject();
    try zlib_mod.constants.put(gzip_file_name, .{ .value = gzip_file_val });

    const gzip_error_name = try vm.intern("Error");
    const gzip_error_val = try vm.newClass(gzip_error_name, error_val.toClassObject());
    try gzip_file_class.module.constants.put(gzip_error_name, .{ .value = gzip_error_val });

    const deflate_name = try vm.intern("Deflate");
    try zlib_mod.constants.put(deflate_name, .{ .value = try vm.newClass(deflate_name, vm.object_class) });
    const inflate_name = try vm.intern("Inflate");
    try zlib_mod.constants.put(inflate_name, .{ .value = try vm.newClass(inflate_name, vm.object_class) });
    const gzip_reader_name = try vm.intern("GzipReader");
    try zlib_mod.constants.put(gzip_reader_name, .{ .value = try vm.newClass(gzip_reader_name, vm.object_class) });
    const gzip_writer_name = try vm.intern("GzipWriter");
    try zlib_mod.constants.put(gzip_writer_name, .{ .value = try vm.newClass(gzip_writer_name, vm.object_class) });

    const zlib_singleton = try vm.getOrCreateSingletonClass(zlib_val);
    try zlib_singleton.module.methods.put(try vm.intern("__deflate"), value.MethodEntry.builtin(&builtinZlibDeflate, .{ .exact = 3 }));
    try zlib_singleton.module.methods.put(try vm.intern("__inflate"), value.MethodEntry.builtin(&builtinZlibInflate, .{ .exact = 2 }));
    try zlib_singleton.module.methods.put(try vm.intern("zlib_version"), value.MethodEntry.builtin(&builtinZlibVersion, .{ .exact = 0 }));
}

pub fn builtinZlibVersion(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return vm.newString("1.3.1", false);
}

pub fn builtinZlibDeflate(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 3);
    const input = try args[0].coerceToStringValue(vm, "no implicit conversion into String");
    const level = try coerceIntegerArg(vm, args[1], "compression level must be an Integer");
    const kind = try coerceContainerKind(vm, args[2]);
    const container = switch (kind) {
        .raw => std.compress.flate.Container.raw,
        .gzip => std.compress.flate.Container.gzip,
        .zlib, .auto => std.compress.flate.Container.zlib,
    };

    const compressed = compressBytes(vm, input.toStringObject().str, container, level) catch |err| {
        return raiseZlibError(vm, kind, err);
    };
    defer vm.allocator.free(compressed);
    return vm.newStringWithEncoding(compressed, false, binary_encoding);
}

pub fn builtinZlibInflate(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    const input = try args[0].coerceToStringValue(vm, "no implicit conversion into String");
    const kind = try coerceContainerKind(vm, args[1]);
    const decompressed = inflateByKind(vm, input.toStringObject().str, kind) catch |err| {
        return raiseZlibError(vm, kind, err);
    };
    defer vm.allocator.free(decompressed);
    return vm.newStringWithEncoding(decompressed, false, binary_encoding);
}

fn coerceIntegerArg(vm: *VM, arg: Value, message: []const u8) VMError!i64 {
    if (!arg.isInteger()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "{s}", .{message});
    }
    return arg.toInteger();
}

fn coerceContainerKind(vm: *VM, arg: Value) VMError!ContainerKind {
    const raw = try coerceIntegerArg(vm, arg, "container kind must be an Integer");
    return switch (raw) {
        0...3 => @enumFromInt(raw),
        else => vm.raiseExceptionFmt(vm.argument_error_class, "unsupported zlib container kind {d}", .{raw}),
    };
}

fn compressionOptions(level: i64) std.compress.flate.Compress.Options {
    return switch (level) {
        0, 1 => .level_1,
        2 => .level_2,
        3 => .level_3,
        4 => .level_4,
        5 => .level_5,
        -1, 6 => .level_6,
        7 => .level_7,
        8 => .level_8,
        9 => .level_9,
        else => if (level < 0) .default else .best,
    };
}

fn compressBytes(vm: *VM, input: []const u8, container: std.compress.flate.Container, level: i64) ![]u8 {
    var output: std.Io.Writer.Allocating = try .initCapacity(vm.allocator, @max(input.len / 2 + 64, 64));
    defer output.deinit();

    var history: [std.compress.flate.max_window_len]u8 = undefined;
    var compressor = try std.compress.flate.Compress.init(&output.writer, &history, container, compressionOptions(level));
    try compressor.writer.writeAll(input);
    try compressor.finish();

    return output.toOwnedSlice();
}

fn inflateByKind(vm: *VM, input: []const u8, kind: ContainerKind) ![]u8 {
    return switch (kind) {
        .raw => inflateBytes(vm, input, .raw),
        .gzip => inflateBytes(vm, input, .gzip),
        .zlib => inflateBytes(vm, input, .zlib),
        .auto => inflateAuto(vm, input),
    };
}

fn inflateAuto(vm: *VM, input: []const u8) ![]u8 {
    if (input.len >= 2 and input[0] == 0x1f and input[1] == 0x8b) {
        return inflateBytes(vm, input, .gzip) catch {
            return inflateBytes(vm, input, .zlib) catch inflateBytes(vm, input, .raw);
        };
    }
    return inflateBytes(vm, input, .zlib) catch inflateBytes(vm, input, .raw);
}

fn inflateBytes(vm: *VM, input: []const u8, container: std.compress.flate.Container) ![]u8 {
    var input_reader: std.Io.Reader = .fixed(input);
    var history: [std.compress.flate.max_window_len]u8 = undefined;
    var decompressor = std.compress.flate.Decompress.init(&input_reader, container, &history);
    var output: std.Io.Writer.Allocating = .init(vm.allocator);
    defer output.deinit();

    while (decompressor.reader.peekGreedy(1)) |bytes| {
        try output.writer.writeAll(bytes);
        decompressor.reader.toss(bytes.len);
    } else |err| switch (err) {
        error.ReadFailed => return decompressor.err orelse error.ReadFailed,
        error.EndOfStream => {},
    }

    return output.toOwnedSlice();
}

fn raiseZlibError(vm: *VM, kind: ContainerKind, err: anyerror) VMError {
    const class = errorClassFor(vm, kind, err) catch return error.Fatal;
    return vm.raiseExceptionFmt(class, "{s}", .{@errorName(err)});
}

fn errorClassFor(vm: *VM, kind: ContainerKind, err: anyerror) VMError!*ClassObject {
    if (kind == .gzip or err == error.BadGzipHeader or err == error.WrongGzipChecksum or err == error.WrongGzipSize) {
        if (try vm.resolveConstantPath("Zlib::GzipFile::Error")) |val| return val.toClassObject();
    }
    if (err == error.BadZlibHeader or err == error.WrongZlibChecksum or err == error.InvalidCode or err == error.InvalidMatch or err == error.WrongStoredBlockNlen or err == error.InvalidBlockType or err == error.InvalidDynamicBlockHeader or err == error.OversubscribedHuffmanTree or err == error.IncompleteHuffmanTree or err == error.MissingEndOfBlockCode or err == error.EndOfStream) {
        if (try vm.resolveConstantPath("Zlib::DataError")) |val| return val.toClassObject();
    }
    if (try vm.resolveConstantPath("Zlib::Error")) |val| return val.toClassObject();
    return vm.standard_error_class;
}
