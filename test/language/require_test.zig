const std = @import("std");

const evalCodeWithOutput = @import("../test_helper.zig").evalCodeWithOutput;
const evalCode = @import("../test_helper.zig").evalCode;

test "require loaded feature lookup tracks load path and loaded feature mutations" {
    const result = try evalCode(
        \\require "tmpdir"
        \\Dir.mktmpdir("cora-require-") do |dir|
        \\  dir = File.realpath(dir)
        \\  original_path = $LOAD_PATH.dup
        \\  original_features = $LOADED_FEATURES.dup
        \\  begin
        \\    left, right = "#{dir}/left", "#{dir}/right"
        \\    [left, right].each { |path| Dir.mkdir(path); Dir.mkdir("#{path}/nested") }
        \\    feature = "nested/cora_fast_require"
        \\    left_file, right_file = "#{left}/#{feature}.rb", "#{right}/#{feature}.rb"
        \\    File.write(left_file, "$fast_require_events << :left")
        \\    File.write(right_file, "$fast_require_events << :right")
        \\    $fast_require_events = []
        \\    $LOAD_PATH.replace([left])
        \\    raise "first load" unless require(feature)
        \\    raise "repeat load" if require(feature)
        \\    raise "explicit extension" if require("#{feature}.rb")
        \\    $LOAD_PATH.unshift(right)
        \\    raise "earlier path shadows loaded Ruby file" if require(feature)
        \\    $LOAD_PATH.shift
        \\    $LOAD_PATH[0] = right
        \\    raise "mutated load path" unless require(feature)
        \\    index = $LOADED_FEATURES.index(right_file)
        \\    entry = right_file.dup
        \\    $LOADED_FEATURES[index] = entry
        \\    entry.replace("#{right}/absent.rb")
        \\    raise "mutated feature entry" unless require(feature)
        \\    $LOADED_FEATURES.delete(right_file)
        \\    raise "removed feature entry" unless require(feature)
        \\    File.unlink(right_file)
        \\    raise "deleted source reloaded" if require(feature)
        \\    driver = "#{dir}/driver.rb"
        \\    File.write(driver, "$fast_require_recursive = require __FILE__; $fast_require_completed = require #{feature.inspect}")
        \\    raise "outer load" unless require(driver)
        \\    raise "recursive load" unless $fast_require_recursive == false
        \\    raise "completed feature during outer load" unless $fast_require_completed == false
        \\    raise "unexpected loads" unless $fast_require_events == [:left, :right, :right, :right]
        \\    true
        \\  ensure
        \\    $LOAD_PATH.replace(original_path)
        \\    $LOADED_FEATURES.replace(original_features)
        \\  end
        \\end
    );
    try std.testing.expect(result.isTrue());
}

test "require synchronizes loaded features without replacing the array or existing strings" {
    const result = try evalCode(
        \\require "tmpdir"
        \\Dir.mktmpdir("cora-feature-sync-") do |dir|
        \\  dir = File.realpath(dir)
        \\  original = $LOADED_FEATURES.dup
        \\  begin
        \\    features = $LOADED_FEATURES
        \\    first = "#{dir}/first.rb"
        \\    inner = "#{dir}/inner.rb"
        \\    outer = "#{dir}/outer.rb"
        \\    driver = "#{dir}/driver.rb"
        \\    File.write(first, "$feature_first_count = ($feature_first_count || 0) + 1")
        \\    File.write(inner, "true")
        \\    File.write(outer, "require_relative 'inner'; $feature_inner_entry = $LOADED_FEATURES.find { |s| s.end_with?('/inner.rb') }; raise 'outer failed'")
        \\    File.write(driver, "require_relative 'first'")
        \\    raise "first load" unless require(first)
        \\    first_entry = features.find { |s| s == first }
        \\    raise "array identity" unless features.equal?($LOADED_FEATURES) && features.equal?($")
        \\    raise "missing path" unless first_entry
        \\    raise "repeat load" if require(first)
        \\    raise "relative load" unless require(driver)
        \\    raise "string identity" unless features.find { |s| s == first }.equal?(first_entry)
        \\    begin
        \\      require(outer)
        \\      raise "expected failure"
        \\    rescue RuntimeError => e
        \\      raise unless e.message == "outer failed"
        \\    end
        \\    raise "failed entry" if features.include?(outer)
        \\    raise "nested entry" unless features.find { |s| s == inner }.equal?($feature_inner_entry)
        \\    raise "nested reload" if require(inner)
        \\    features.delete(first)
        \\    raise "removed entry reload" unless require(first) && $feature_first_count == 2
        \\    replacement = first.dup
        \\    features[features.index(first)] = replacement
        \\    replacement.replace("#{dir}/absent.rb")
        \\    raise "mutated entry reload" unless require(first) && $feature_first_count == 3
        \\    GC.start
        \\    raise "array changed" unless features.equal?($LOADED_FEATURES)
        \\    true
        \\  ensure
        \\    $LOADED_FEATURES.replace(original)
        \\  end
        \\end
    );
    try std.testing.expect(result.isTrue());
}

test "require prefers an unloaded Ruby source over a loaded native feature" {
    const result = try evalCode(
        \\require "tmpdir"
        \\Dir.mktmpdir("cora-require-native-") do |dir|
        \\  dir = File.realpath(dir)
        \\  original_features = $LOADED_FEATURES.dup
        \\  begin
        \\    $LOAD_PATH.unshift(dir)
        \\    File.write("#{dir}/cora_fast_native.rb", "$fast_native_loaded = true")
        \\    $LOADED_FEATURES << "#{dir}/cora_fast_native.so"
        \\    require("cora_fast_native") && $fast_native_loaded
        \\  ensure
        \\    $LOAD_PATH.delete(dir)
        \\    $LOADED_FEATURES.replace(original_features)
        \\  end
        \\end
    );
    try std.testing.expect(result.isTrue());
}

test "require loads RubyGems after extending $LOAD_PATH" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{
            "zig-out/bin/cora",
            "-Izig-out/ext/rubygems/lib",
            "-e",
            "require \"rubygems/version\"; require \"rubygems/requirement\"; puts Gem::Requirement.default.to_s",
        },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualSlices(u8, ">= 0\n", result.stdout);
}

test "require runs Ruby files at top level lexical scope" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{
            "zig-out/bin/cora",
            "-Izig-out/ext/rubygems/lib",
            "-e",
            "require \"rubygems/version\"; class ScopeCarrier; require File.expand_path(\"zig-out/ext/rubygems/lib/rubygems/requirement\", Dir.pwd); end; puts Gem::Requirement.default.to_s",
        },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualSlices(u8, ">= 0\n", result.stdout);
}

test "stdlib require loads monitor by default" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{ "zig-out/bin/cora", "-e", "require \"monitor\"; puts Monitor.new.synchronize { 1 }" },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualSlices(u8, "1\n", result.stdout);
}

test "MonitorMixin initializes included classes and extended objects" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{
            "zig-out/bin/cora",
            "-e",
            "require \"monitor\"; klass = Class.new { include MonitorMixin }; puts klass.new.synchronize { 1 }; object = Object.new; object.extend(MonitorMixin); puts object.synchronize { 2 }",
        },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualSlices(u8, "1\n2\n", result.stdout);
}

test "dash r with separate argument requires library before eval" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{ "zig-out/bin/cora", "-r", "set", "-e", "puts Set.new([1, 2, 2]).size" },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualSlices(u8, "2\n", result.stdout);
}

test "dash r attached argument requires library before eval" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{ "zig-out/bin/cora", "-rset", "-e", "puts Set.new([1, 2, 2]).size" },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualSlices(u8, "2\n", result.stdout);
}

test "stdlib require loads set by default" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{
            "zig-out/bin/cora",
            "-e",
            "require \"set\"; s = Set.new([1, 2, 2]); s.add(3); puts [s.include?(2), s.size, (s & [2, 4]).to_a[0]].inspect",
        },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualSlices(u8, "[true, 3, 2]\n", result.stdout);
}

test "top level Set autoloads stdlib set" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{ "zig-out/bin/cora", "-e", "puts Set.new([1, 2, 2]).size" },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualSlices(u8, "2\n", result.stdout);
}

test "stdlib require loads thread condition variable" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{
            "zig-out/bin/cora",
            "-e",
            \\require "thread"
            \\mutex = Thread::Mutex.new
            \\cv = ConditionVariable.new
            \\ready = false
            \\waiting = false
            \\t = Thread.new do
            \\  mutex.synchronize do
            \\    waiting = true
            \\    cv.wait(mutex, 1.0)
            \\    puts ready
            \\  end
            \\end
            \\Thread.pass until waiting
            \\mutex.synchronize do
            \\  ready = true
            \\  cv.signal
            \\end
            \\t.join
            ,
        },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualSlices(u8, "true\n", result.stdout);
}
