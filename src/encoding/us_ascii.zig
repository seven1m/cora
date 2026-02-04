const encoding = @import("../encoding.zig");

pub const UsAsciiEncoding = struct {
    pub fn name(_: UsAsciiEncoding) []const u8 {
        return "US-ASCII";
    }

    pub fn nextChar(_: UsAsciiEncoding, bytes: []const u8, index: *usize) encoding.CharResult {
        if (index.* >= bytes.len) return .{ .valid = true, .len = 0 };
        const b = bytes[index.*];
        index.* += 1;
        return .{ .valid = b <= 127, .len = 1 };
    }

    pub fn isValid(_: UsAsciiEncoding, bytes: []const u8) bool {
        for (bytes) |b| {
            if (b > 127) return false;
        }
        return true;
    }

    pub fn isAsciiCompatible(_: UsAsciiEncoding) bool {
        return true;
    }

    pub fn isSingleByte(_: UsAsciiEncoding) bool {
        return true;
    }
};
