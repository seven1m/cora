const ruby_gem_api_version = "4.0.0";

fn defaultGemLibPath(comptime name: []const u8, comptime version: []const u8) []const u8 {
    return "lib/gems/" ++ ruby_gem_api_version ++ "/gems/" ++ name ++ "-" ++ version ++ "/lib";
}

pub const repo_load_paths = [_][]const u8{
    "lib/stdlib",
    "ext/rubygems/lib",
    "ext/logger/lib",
    "ext/delegate/lib",
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
    defaultGemLibPath("psych", "5.4.0"),
    defaultGemLibPath("strscan", "3.1.9"),
};
