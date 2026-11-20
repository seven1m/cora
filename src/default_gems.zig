const std = @import("std");

pub const Source = enum { repository, bundler, psych, strscan, json, stdlib };
pub const Gem = struct {
    name: []const u8,
    version: []const u8,
    source: Source = .repository,
    load_path: bool = false,
};

// Order also controls the installed default gems' load-path precedence.
pub const gems = [_]Gem{
    .{ .name = "psych", .version = "5.4.0", .source = .psych, .load_path = true },
    .{ .name = "strscan", .version = "3.1.8", .source = .strscan, .load_path = true },
    .{ .name = "json", .version = "2.19.9", .source = .json, .load_path = true },
    .{ .name = "bundler", .version = "4.1.0.dev", .source = .bundler, .load_path = true },
    .{ .name = "prettyprint", .version = "0.2.1", .load_path = true },
    .{ .name = "pp", .version = "0.6.4", .load_path = true },
    .{ .name = "net-http", .version = "0.10.0", .load_path = true },
    .{ .name = "net-protocol", .version = "0.4.0", .load_path = true },
    .{ .name = "open-uri", .version = "0.5.0", .load_path = true },
    .{ .name = "resolv", .version = "0.6.2", .load_path = true },
    .{ .name = "yaml", .version = "0.4.0" },
    .{ .name = "did_you_mean", .version = "2.0.0" },
    .{ .name = "timeout", .version = "0.6.1" },
    .{ .name = "uri", .version = "1.1.1" },
    .{ .name = "time", .version = "0.4.2" },
    // These use temporary minimal gemspecs until ported from lib/stdlib.
    .{ .name = "stringio", .version = "3.2.0", .source = .stdlib },
    .{ .name = "date", .version = "3.5.1", .source = .stdlib },
};

pub fn version(comptime name: []const u8) []const u8 {
    inline for (gems) |gem| {
        if (comptime std.mem.eql(u8, gem.name, name)) return gem.version;
    }
    @compileError("unknown default gem: " ++ name);
}
