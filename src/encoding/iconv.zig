const builtin = @import("builtin");
const std = @import("std");

extern "c" fn iconv_open(to_code: [*:0]const u8, from_code: [*:0]const u8) *anyopaque;
extern "c" fn iconv_close(descriptor: *anyopaque) c_int;
extern "c" fn iconv(
    descriptor: *anyopaque,
    input: ?*?[*]u8,
    input_left: ?*usize,
    output: *?[*]u8,
    output_left: *usize,
) usize;

const invalid_descriptor = @as(usize, std.math.maxInt(usize));
const iconv_failure = std.math.maxInt(usize);

pub const Decoded = struct {
    codepoint: u32,
    consumed: usize,
};

pub fn decodeFirst(from_code: [:0]const u8, bytes: []const u8) ?Decoded {
    if (builtin.os.tag == .windows or bytes.len == 0) return null;
    const descriptor = iconv_open("UTF-32LE", from_code.ptr);
    if (@intFromPtr(descriptor) == invalid_descriptor) return null;
    defer _ = iconv_close(descriptor);

    var out: [4]u8 = undefined;
    var out_ptr: ?[*]u8 = &out;
    var out_left: usize = out.len;
    var in_ptr: ?[*]u8 = @ptrCast(@constCast(bytes.ptr));
    var in_left = bytes.len;
    _ = iconv(descriptor, &in_ptr, &in_left, &out_ptr, &out_left);

    const consumed = bytes.len - in_left;
    if (consumed == 0 or out_left != 0) return null;
    return .{
        .codepoint = @as(u32, out[0]) |
            (@as(u32, out[1]) << 8) |
            (@as(u32, out[2]) << 16) |
            (@as(u32, out[3]) << 24),
        .consumed = consumed,
    };
}

pub fn encodeCodepoint(to_code: [:0]const u8, codepoint: u32, out: *[4]u8) ?usize {
    if (builtin.os.tag == .windows) return null;
    if (codepoint > 0x10FFFF) return null;

    const descriptor = iconv_open(to_code.ptr, "UTF-8");
    if (@intFromPtr(descriptor) == invalid_descriptor) return null;
    defer _ = iconv_close(descriptor);

    var utf8: [4]u8 = undefined;
    const utf8_len = std.unicode.utf8Encode(@intCast(codepoint), &utf8) catch return null;
    var in_ptr: ?[*]u8 = &utf8;
    var in_left: usize = utf8_len;
    var out_ptr: ?[*]u8 = out;
    var out_left: usize = out.len;
    const result = iconv(descriptor, &in_ptr, &in_left, &out_ptr, &out_left);
    if (result == iconv_failure or in_left != 0) return null;
    return out.len - out_left;
}

pub fn transcode(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    from_code: [:0]const u8,
    to_code: [:0]const u8,
) std.mem.Allocator.Error!?[]u8 {
    if (builtin.os.tag == .windows) return null;

    const unicode = (try convert(allocator, bytes, from_code, "UTF-8")) orelse return null;
    defer allocator.free(unicode);
    return convert(allocator, unicode, "UTF-8", to_code);
}

fn convert(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    from_code: [:0]const u8,
    to_code: [:0]const u8,
) std.mem.Allocator.Error!?[]u8 {
    if (builtin.os.tag == .windows) return null;
    const descriptor = iconv_open(to_code.ptr, from_code.ptr);
    if (@intFromPtr(descriptor) == invalid_descriptor) return null;
    defer _ = iconv_close(descriptor);

    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(allocator);

    var in_ptr: ?[*]u8 = if (bytes.len == 0) null else @ptrCast(@constCast(bytes.ptr));
    var in_left = bytes.len;
    while (in_left > 0) {
        var buffer: [4096]u8 = undefined;
        var out_ptr: ?[*]u8 = &buffer;
        var out_left: usize = buffer.len;
        const before = in_left;
        const result = iconv(descriptor, &in_ptr, &in_left, &out_ptr, &out_left);
        const produced = buffer.len - out_left;
        output.appendSlice(allocator, buffer[0..produced]) catch return error.OutOfMemory;

        if (result != iconv_failure) continue;
        if (out_left == 0 and (produced > 0 or in_left < before)) continue;
        return null;
    }

    // Flush any shift state into the output (needed by stateful targets).
    while (true) {
        var buffer: [4096]u8 = undefined;
        var out_ptr: ?[*]u8 = &buffer;
        var out_left: usize = buffer.len;
        const result = iconv(descriptor, null, null, &out_ptr, &out_left);
        const produced = buffer.len - out_left;
        output.appendSlice(allocator, buffer[0..produced]) catch return error.OutOfMemory;
        if (result != iconv_failure) break;
        if (out_left != 0) return null;
    }

    return output.toOwnedSlice(allocator) catch return error.OutOfMemory;
}
