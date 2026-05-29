const std = @import("std");
const builtin = @import("builtin");

pub const ruby_version = "4.0.0";
pub const ruby_patch = "0";
pub const description = std.fmt.comptimePrint("cora {s}p{s} ({s}-{s})", .{ ruby_version, ruby_patch, @tagName(builtin.cpu.arch), @tagName(builtin.os.tag) });
