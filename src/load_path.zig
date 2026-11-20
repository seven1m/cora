const default_gems = @import("default_gems.zig");
const ruby_gem_api_version = "4.1.0";

fn defaultGemLibPath(comptime name: []const u8, comptime version: []const u8) []const u8 {
    return "lib/gems/" ++ ruby_gem_api_version ++ "/gems/" ++ name ++ "-" ++ version ++ "/lib";
}

const builtin_load_paths = [_][]const u8{
    "lib/stdlib",
    "ext/rubygems/lib",
    "ext/ipaddr/lib",
    "ext/logger/lib",
    "ext/delegate/lib",
    "ext/did_you_mean/lib",
    "ext/forwardable/lib",
    "ext/time/lib",
    "ext/timeout/lib",
    "ext/singleton/lib",
    "ext/optparse/lib",
    "ext/psych/lib",
    "ext/uri/lib",
    "ext/tmpdir/lib",
    "ext/tempfile/lib",
    "ext/yaml/lib",
    "ext/cgi/lib",
    "ext/erb/lib",
    "ext/open3/lib",
    "ext/shellwords/lib",
    "ext/weakref/lib",
};

pub const default_gem_load_paths_start = builtin_load_paths.len;
pub const repo_load_paths = builtin_load_paths ++ installed_default_paths;

const installed_default_paths = paths: {
    var count: usize = 0;
    for (default_gems.gems) |gem| {
        if (gem.load_path) count += 1;
    }
    var paths: [count][]const u8 = undefined;
    var index: usize = 0;
    for (default_gems.gems) |gem| {
        if (gem.load_path) {
            paths[index] = defaultGemLibPath(gem.name, gem.version);
            index += 1;
        }
    }
    break :paths paths;
};
