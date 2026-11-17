const std = @import("std");
const builtin = @import("builtin");

pub const ruby_version = "4.1.0";
pub const ruby_patch = "0";
pub const host_cpu = if (builtin.os.tag.isDarwin() and builtin.cpu.arch == .aarch64) "arm64" else @tagName(builtin.cpu.arch);
pub const platform = std.fmt.comptimePrint("{s}-{s}", .{ host_cpu, if (builtin.os.tag.isDarwin()) "darwin" else @tagName(builtin.os.tag) });
pub const description = std.fmt.comptimePrint("cora {s}p{s} ({s})", .{ ruby_version, ruby_patch, platform });
