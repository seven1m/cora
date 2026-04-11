const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;
const evalFile = test_helper.evalFile;

test "p with no arguments" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;

    const result = evalCodeWithOutput("p", &stdout_buf, &stderr_buf);
    try std.testing.expect(result.value.isNil());
    try std.testing.expectEqualStrings("\n", result.stdout);
}

test "p with single integer" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;

    const result = evalCodeWithOutput("p 42", &stdout_buf, &stderr_buf);
    try std.testing.expect(result.value.isInteger());
    try std.testing.expectEqual(@as(i64, 42), result.value.toInteger());
    try std.testing.expectEqualStrings("42\n", result.stdout);
}

test "p with single string" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;

    const result = evalCodeWithOutput("p \"hello\"", &stdout_buf, &stderr_buf);
    try std.testing.expect(result.value.isString());
    try std.testing.expectEqualSlices(u8, "hello", result.value.toStringObject().str);
    try std.testing.expectEqualStrings("\"hello\"\n", result.stdout);
}

test "p with multiple integers" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;

    const result = evalCodeWithOutput("p 1, 2, 3", &stdout_buf, &stderr_buf);
    try std.testing.expect(result.value.isArray());
    try std.testing.expectEqual(@as(usize, 3), result.value.toArrayObject().elements.items.len);
    try std.testing.expectEqualStrings("1\n2\n3\n", result.stdout);
}

test "p with mixed types" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;

    const result = evalCodeWithOutput("p 42, \"hello\", :foo", &stdout_buf, &stderr_buf);
    try std.testing.expect(result.value.isArray());
    try std.testing.expectEqual(@as(usize, 3), result.value.toArrayObject().elements.items.len);
    try std.testing.expectEqualStrings("42\n\"hello\"\n:foo\n", result.stdout);
}

test "puts" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;

    var result = evalCodeWithOutput("puts [1, 2, 3], [4, 5, 6]", &stdout_buf, &stderr_buf);
    try std.testing.expectEqualStrings("1\n2\n3\n4\n5\n6\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);

    result = evalCodeWithOutput("puts", &stdout_buf, &stderr_buf);
    try std.testing.expectEqualStrings("\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

test "Kernel#nil? returns false for non-nil" {
    const result = try evalCode("1.nil?");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(false, result.toBool());
}

test "Kernel#freeze returns receiver and marks String frozen" {
    const result = try evalCode("s = \"hello\"; s.freeze.object_id == s.object_id && s.frozen?");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());
}

test "Kernel#freeze marks Hash frozen and prevents mutation" {
    const frozen_result = try evalCode("h = {}; h.freeze; h.frozen?");
    try std.testing.expect(frozen_result.isBool());
    try std.testing.expectEqual(true, frozen_result.toBool());

    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const mutation = evalCodeWithOutput("h = {}; h.freeze; h[:x] = 1", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, mutation.err.?);
}

test "Kernel#freeze on Integer is a no-op and remains frozen" {
    const result = try evalCode("i = 42; i.freeze.object_id == i.object_id && i.frozen?");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());
}

test "Kernel#instance_of? returns true for exact class and false for ancestor/module" {
    var result = try evalCode("\"\".instance_of?(String)");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());

    result = try evalCode(
        \\class A
        \\end
        \\class B < A
        \\end
        \\B.new.instance_of?(A)
    );
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(false, result.toBool());

    result = try evalCode(
        \\module M
        \\end
        \\class C
        \\  include M
        \\end
        \\C.new.instance_of?(M)
    );
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(false, result.toBool());
}

test "Kernel#instance_of? raises TypeError for non class/module argument" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    var bad = evalCodeWithOutput("Object.new.instance_of?(Object.new)", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "TypeError") != null);

    bad = evalCodeWithOutput("Object.new.instance_of?(1)", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "TypeError") != null);
}

test "Kernel#respond_to? supports symbol/string names and include_private" {
    var result = try evalCode(
        \\class K
        \\  def pub_method
        \\    1
        \\  end
        \\end
        \\k = K.new
        \\[k.respond_to?(:pub_method), k.respond_to?("pub_method"), k.respond_to?(:missing_method)]
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[0].toBool());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[1].toBool());
    try std.testing.expectEqual(false, result.toArrayObject().elements.items[2].toBool());

    result = try evalCode(
        \\class K
        \\  protected
        \\  def protected_method
        \\    1
        \\  end
        \\  private
        \\  def private_method
        \\    2
        \\  end
        \\end
        \\k = K.new
        \\[
        \\  k.respond_to?(:protected_method),
        \\  k.respond_to?(:private_method),
        \\  k.respond_to?(:protected_method, false),
        \\  k.respond_to?(:private_method, false),
        \\  k.respond_to?(:protected_method, true),
        \\  k.respond_to?(:private_method, true)
        \\]
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(false, result.toArrayObject().elements.items[0].toBool());
    try std.testing.expectEqual(false, result.toArrayObject().elements.items[1].toBool());
    try std.testing.expectEqual(false, result.toArrayObject().elements.items[2].toBool());
    try std.testing.expectEqual(false, result.toArrayObject().elements.items[3].toBool());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[4].toBool());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[5].toBool());
}

test "Kernel#respond_to? raises for invalid argument types and arity" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    var bad = evalCodeWithOutput("Object.new.respond_to?(Object.new)", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "TypeError") != null);

    bad = evalCodeWithOutput("Object.new.respond_to?", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "ArgumentError") != null);

    bad = evalCodeWithOutput("Object.new.respond_to?(:to_s, true, false)", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "ArgumentError") != null);
}

test "Kernel#respond_to? coerces method name via to_str" {
    const result = try evalCode(
        \\obj = Object.new
        \\def obj.foo
        \\  1
        \\end
        \\name = Object.new
        \\def name.to_str
        \\  "foo"
        \\end
        \\obj.respond_to?(name)
    );
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());
}

test "Kernel#respond_to? consults respond_to_missing? for missing methods" {
    const result = try evalCode(
        \\class RespondToMissingHookSpec
        \\  def respond_to_missing?(name, include_private = false)
        \\    @calls ||= []
        \\    @calls << [name, include_private]
        \\    name.to_s == "dynamic_method"
        \\  end
        \\
        \\  def calls
        \\    @calls
        \\  end
        \\end
        \\obj = RespondToMissingHookSpec.new
        \\first = obj.respond_to?(:to_s)
        \\second = obj.respond_to?(:dynamic_method)
        \\calls = obj.calls
        \\[first, second, calls.length]
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[0].toBool());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[1].toBool());
    try std.testing.expectEqual(@as(i64, 1), result.toArrayObject().elements.items[2].toInteger());
}

test "Kernel#respond_to? include_private controls respond_to_missing? fallback" {
    const result = try evalCode(
        \\class RespondToMissingVisibilitySpec
        \\  def initialize
        \\    @last = nil
        \\  end
        \\
        \\  def respond_to_missing?(name, include_private = false)
        \\    @last = [name, include_private]
        \\    false
        \\  end
        \\
        \\  def last
        \\    @last
        \\  end
        \\
        \\  private
        \\  def hidden
        \\    :x
        \\  end
        \\end
        \\obj = RespondToMissingVisibilitySpec.new
        \\first = obj.respond_to?(:hidden)
        \\first_last = obj.last
        \\second = obj.respond_to?(:hidden, true)
        \\second_last = obj.last
        \\[first, first_last[0], first_last[1], second, second_last[0], second_last[1]]
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(false, result.toArrayObject().elements.items[0].toBool());
    try std.testing.expectEqualStrings("hidden", result.toArrayObject().elements.items[1].toSymbolObject().name);
    try std.testing.expectEqual(false, result.toArrayObject().elements.items[2].toBool());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[3].toBool());
    try std.testing.expectEqualStrings("hidden", result.toArrayObject().elements.items[4].toSymbolObject().name);
    try std.testing.expectEqual(false, result.toArrayObject().elements.items[5].toBool());
}

test "BasicObject#initialize is private and Class#new dispatches through method_missing after undef_method" {
    var result = try evalCode("Object.new.respond_to?(:initialize, true)");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());

    result = try evalCode("Object.new.send(:initialize).nil?");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());

    result = try evalCode(
        \\$init_calls = nil
        \\class ConstructorMissingSpec
        \\  undef_method :initialize
        \\
        \\  def respond_to_missing?(name, include_private = false)
        \\    name == :initialize
        \\  end
        \\
        \\  def method_missing(name, *args)
        \\    $init_calls = [name, args]
        \\  end
        \\end
        \\
        \\obj = ConstructorMissingSpec.new(1, 2)
        \\[$init_calls[0], $init_calls[1][0], $init_calls[1][1], obj.class == ConstructorMissingSpec]
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqualSlices(u8, "initialize", result.toArrayObject().elements.items[0].toSymbolObject().name);
    try std.testing.expectEqual(@as(i64, 1), result.toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 2), result.toArrayObject().elements.items[2].toInteger());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[3].toBool());
}

test "Kernel lifecycle copy helpers match default dispatch behavior" {
    var result = try evalCode(
        \\obj = Object.new
        \\obj.send(:initialize_copy, obj).equal?(obj)
    );
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());

    result = try evalCode(
        \\obj = Object.new
        \\other = Object.new
        \\[obj.send(:initialize_dup, other).equal?(obj), obj.send(:initialize_clone, other, freeze: true).equal?(obj)]
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[0].toBool());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[1].toBool());

    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;

    var bad = evalCodeWithOutput(
        \\Object.new.freeze.send(:initialize_copy, Object.new)
    , &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "FrozenError") != null);

    bad = evalCodeWithOutput(
        \\class A
        \\end
        \\class B < A
        \\end
        \\A.new.send(:initialize_copy, B.new)
    , &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "TypeError") != null);
}

test "Array literal preserves side effects across respond_to? calls" {
    const result = try evalCode(
        \\class RespondToMissingHookSpec
        \\  def respond_to_missing?(name, include_private = false)
        \\    @calls ||= []
        \\    @calls << [name, include_private]
        \\    name.to_s == "dynamic_method"
        \\  end
        \\
        \\  def calls
        \\    @calls
        \\  end
        \\end
        \\obj = RespondToMissingHookSpec.new
        \\[obj.respond_to?(:to_s), obj.respond_to?(:dynamic_method), obj.calls.length]
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[0].toBool());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[1].toBool());
    try std.testing.expectEqual(@as(i64, 1), result.toArrayObject().elements.items[2].toInteger());
}

test "Kernel#send coerces method name via to_str" {
    const result = try evalCode(
        \\obj = Object.new
        \\def obj.foo
        \\  42
        \\end
        \\name = Object.new
        \\def name.to_str
        \\  "foo"
        \\end
        \\obj.send(name)
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
}

test "Kernel#to_enum and #enum_for return Enumerator and default to #each" {
    var result = try evalCode("[1, 2].to_enum");
    try std.testing.expect(result.isEnumerator());

    result = try evalCode("[1, 2].enum_for");
    try std.testing.expect(result.isEnumerator());

    result = try evalCode(
        \\e = [1, 2].to_enum
        \\[e.next, e.next]
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(i64, 1), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 2), result.toArrayObject().elements.items[1].toInteger());
}

test "Kernel#to_enum forwards method name and arguments" {
    const result = try evalCode(
        \\obj = Object.new
        \\def obj.repeat(n)
        \\  i = 0
        \\  while i < n
        \\    yield i
        \\    i = i + 1
        \\  end
        \\end
        \\e = obj.to_enum(:repeat, 3)
        \\[e.next, e.next, e.next]
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(i64, 0), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 1), result.toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 2), result.toArrayObject().elements.items[2].toInteger());
}

test "Kernel#to_enum coerces method name via to_str" {
    const result = try evalCode(
        \\obj = Object.new
        \\def obj.each
        \\  yield 9
        \\end
        \\name = Object.new
        \\def name.to_str
        \\  "each"
        \\end
        \\obj.to_enum(name).next
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 9), result.toInteger());
}

test "Kernel#enum_for block is deferred and used by Enumerator#size" {
    const result = try evalCode(
        \\calls = 0
        \\e = Object.new.enum_for do
        \\  calls = calls + 1
        \\  123
        \\end
        \\before = calls
        \\value = e.size
        \\after = calls
        \\[before, value, after]
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(i64, 0), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 123), result.toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 1), result.toArrayObject().elements.items[2].toInteger());
}

test "Kernel#eval returns expression result" {
    const result = try evalCode("eval(\"1 + 2\")");
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 3), result.toInteger());
}

test "Kernel#eval uses caller self" {
    const result = try evalCode(
        \\obj = Object.new
        \\obj.instance_variable_set(:@x, 41)
        \\def obj.read_x
        \\  eval("@x + 1")
        \\end
        \\obj.read_x
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
}

test "Kernel#eval parses endless range literals" {
    const result = try evalCode(
        \\r = eval("(2..)")
        \\[r.begin, r.end.nil?, r.exclude_end?]
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(i64, 2), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[1].toBool());
    try std.testing.expectEqual(false, result.toArrayObject().elements.items[2].toBool());
}

test "Kernel#eval preserves non-UTF-8 source encoding" {
    const result = try evalCode(
        \\external = Encoding.default_external
        \\Encoding.default_external = Encoding::Windows_31J
        \\sjis_hash = "{\x87]: 1}".dup.force_encoding("sjis")
        \\begin
        \\  h = eval(sjis_hash)
        \\  key = h.keys[0]
        \\  [key.encoding.name, h.inspect == sjis_hash, h.inspect.encoding.name]
        \\ensure
        \\  Encoding.default_external = external
        \\end
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 3), result.toArrayObject().elements.items.len);
    try std.testing.expectEqualSlices(u8, "Windows-31J", result.toArrayObject().elements.items[0].toStringObject().str);
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[1].toBool());
    try std.testing.expectEqualSlices(u8, "Windows-31J", result.toArrayObject().elements.items[2].toStringObject().str);
}

test "Kernel#eval raises TypeError when source is not String-like" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const bad = evalCodeWithOutput("eval(Object.new)", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "TypeError") != null);
}

test "Kernel#eval raises SyntaxError for invalid source" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const bad = evalCodeWithOutput("eval(\"def\")", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "SyntaxError") != null);
}

test "Kernel#eval returns nil for __dir__ with top-level binding" {
    const result = try evalCode("eval(\"__dir__\", binding)");
    try std.testing.expect(result.isNil());
}

test "File.realpath resolves the executing file directory" {
    const allocator = std.testing.allocator;
    const dir_path = try std.fmt.allocPrint(allocator, "/tmp/cora-file-realpath-{d}", .{std.time.nanoTimestamp()});
    defer allocator.free(dir_path);
    try std.fs.makeDirAbsolute(dir_path);
    defer std.fs.deleteTreeAbsolute(dir_path) catch {};

    const file_path = try std.fmt.allocPrint(allocator, "{s}/realpath.rb", .{dir_path});
    defer allocator.free(file_path);

    const file = try std.fs.createFileAbsolute(file_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll("File.realpath(File.dirname(__FILE__))\n");

    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const result = evalFile(file_path, &stdout_buf, &stderr_buf);
    if (result.err) |err| return err;

    const expected = try std.fs.realpathAlloc(allocator, dir_path);
    defer allocator.free(expected);

    try std.testing.expect(result.value.isString());
    try std.testing.expectEqualStrings(expected, result.value.toStringObject().str);
}

test "Dir.chdir restores cwd after block" {
    const allocator = std.testing.allocator;
    const original = try std.process.getCwdAlloc(allocator);
    defer allocator.free(original);

    const dir_path = try std.fmt.allocPrint(allocator, "/tmp/cora-dir-chdir-{d}", .{std.time.nanoTimestamp()});
    defer allocator.free(dir_path);
    try std.fs.makeDirAbsolute(dir_path);
    defer std.fs.deleteTreeAbsolute(dir_path) catch {};

    const ruby_code = try std.fmt.allocPrint(
        allocator,
        "before = Dir.pwd; inside = nil; after = nil; Dir.chdir(\"{s}\") {{ inside = Dir.pwd }}; after = Dir.pwd; [before, inside, after]",
        .{dir_path},
    );
    defer allocator.free(ruby_code);

    const result = try evalCode(ruby_code);
    try std.testing.expect(result.isArray());
    try std.testing.expectEqualStrings(original, result.toArrayObject().elements.items[0].toStringObject().str);
    try std.testing.expectEqualStrings(dir_path, result.toArrayObject().elements.items[1].toStringObject().str);
    try std.testing.expectEqualStrings(original, result.toArrayObject().elements.items[2].toStringObject().str);
}

test "Kernel#__dir__ returns dot for eval code" {
    const result = try evalCode("__dir__");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, ".", result.toStringObject().str);
}

test "Kernel#__dir__ returns absolute directory for file execution" {
    const allocator = std.testing.allocator;
    const file_path = try std.fmt.allocPrint(
        allocator,
        "/tmp/cora-kernel-dir-{d}.rb",
        .{std.time.nanoTimestamp()},
    );
    defer allocator.free(file_path);

    const file = try std.fs.createFileAbsolute(file_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll("__dir__\n");

    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const result = evalFile(file_path, &stdout_buf, &stderr_buf);
    defer std.fs.deleteFileAbsolute(file_path) catch {};

    if (result.err) |err| return err;

    try std.testing.expect(result.value.isString());
    try std.testing.expectEqualSlices(u8, "/tmp", result.value.toStringObject().str);
}

test "Kernel#instance_variable_get coerces name via to_str and invalid names raise NameError" {
    const result = try evalCode(
        \\obj = Object.new
        \\obj.instance_variable_set(:@x, 9)
        \\name = Object.new
        \\def name.to_str
        \\  "@x"
        \\end
        \\obj.instance_variable_get(name)
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 9), result.toInteger());

    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const bad = evalCodeWithOutput(
        \\obj = Object.new
        \\name = Object.new
        \\def name.to_str
        \\  "x"
        \\end
        \\obj.instance_variable_get(name)
    , &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "NameError") != null);
}

test "Kernel#singleton_class returns singleton class for object" {
    const result = try evalCode(
        \\obj = Object.new
        \\[obj.singleton_class, obj.singleton_class]
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 2), result.toArrayObject().elements.items.len);
    try std.testing.expect(result.toArrayObject().elements.items[0].isClass());
    try std.testing.expect(result.toArrayObject().elements.items[1].isClass());
    try std.testing.expect(
        result.toArrayObject().elements.items[0].toClassObject() == result.toArrayObject().elements.items[1].toClassObject(),
    );
}

test "Kernel#singleton_class returns NilClass/TrueClass/FalseClass for immediates" {
    var result = try evalCode("nil.singleton_class");
    try std.testing.expect(result.isClass());
    try std.testing.expectEqualStrings("NilClass", result.toClassObject().module.name.name);

    result = try evalCode("true.singleton_class");
    try std.testing.expect(result.isClass());
    try std.testing.expectEqualStrings("TrueClass", result.toClassObject().module.name.name);

    result = try evalCode("false.singleton_class");
    try std.testing.expect(result.isClass());
    try std.testing.expectEqualStrings("FalseClass", result.toClassObject().module.name.name);
}

test "Kernel#singleton_class raises TypeError for Integer, Float, and Symbol" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    var bad = evalCodeWithOutput("123.singleton_class", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "TypeError") != null);

    bad = evalCodeWithOutput(":foo.singleton_class", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "TypeError") != null);

    bad = evalCodeWithOutput("1.5.singleton_class", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "TypeError") != null);
}

test "Kernel#singleton_class returns frozen singleton class for frozen object" {
    const result = try evalCode(
        \\obj = Object.new
        \\obj.freeze
        \\obj.singleton_class.frozen?
    );
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());
}

test "Kernel#methods includes singleton and protected methods and excludes private" {
    const result = try evalCode(
        \\class KernelMethodsVisibilitySpec
        \\  protected
        \\  def prot_instance_marker; end
        \\  private
        \\  def priv_instance_marker; end
        \\end
        \\obj = KernelMethodsVisibilitySpec.new
        \\obj.define_singleton_method(:pub_singleton_marker) { 1 }
        \\methods = obj.methods
        \\[
        \\  methods.include?(:pub_singleton_marker),
        \\  methods.include?(:prot_instance_marker),
        \\  methods.include?(:priv_instance_marker)
        \\]
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[0].toBool());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[1].toBool());
    try std.testing.expectEqual(false, result.toArrayObject().elements.items[2].toBool());
}

test "Kernel#methods(false) returns only singleton methods" {
    const result = try evalCode(
        \\obj = Object.new
        \\obj.define_singleton_method(:only_singleton_marker) { 1 }
        \\methods = obj.methods(false)
        \\[
        \\  methods.include?(:only_singleton_marker),
        \\  methods.include?(:object_id)
        \\]
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[0].toBool());
    try std.testing.expectEqual(false, result.toArrayObject().elements.items[1].toBool());
}

test "BasicObject#__id__ returns stable object identity" {
    const result = try evalCode(
        \\obj = Object.new
        \\[obj.__id__ == obj.object_id, [].dup.__id__ == [].dup.__id__]
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[0].toBool());
    try std.testing.expectEqual(false, result.toArrayObject().elements.items[1].toBool());
}

test "Kernel#private_methods includes inherited private methods by default" {
    const result = try evalCode(
        \\class PrivateBaseForMethods
        \\  private
        \\  def inherited_private_marker; end
        \\end
        \\class PrivateChildForMethods < PrivateBaseForMethods
        \\end
        \\obj = PrivateChildForMethods.new
        \\obj.private_methods.include?(:inherited_private_marker)
    );
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());
}

test "Kernel#private_methods(false) excludes ancestor private methods" {
    const result = try evalCode(
        \\class PrivateBaseForMethodsFalse
        \\  private
        \\  def base_private_marker; end
        \\end
        \\class PrivateChildForMethodsFalse < PrivateBaseForMethodsFalse
        \\  private
        \\  def child_private_marker; end
        \\end
        \\obj = PrivateChildForMethodsFalse.new
        \\methods = obj.private_methods(false)
        \\[
        \\  methods.include?(:base_private_marker),
        \\  methods.include?(:child_private_marker)
        \\]
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(false, result.toArrayObject().elements.items[0].toBool());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[1].toBool());
}

test "Kernel#methods and #private_methods validate arg count" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    var bad = evalCodeWithOutput("Object.new.methods(true, false)", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "ArgumentError") != null);

    bad = evalCodeWithOutput("Object.new.private_methods(true, false)", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "ArgumentError") != null);
}

test "Kernel#tap yields self and returns self" {
    const result = try evalCode(
        \\obj = Object.new
        \\seen = nil
        \\ret = obj.tap { |o| seen = o.object_id; 42 }
        \\[ret.object_id == obj.object_id, seen == obj.object_id]
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[0].toBool());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[1].toBool());
}

test "Kernel#tap raises LocalJumpError when no block is given" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const bad = evalCodeWithOutput("Object.new.tap", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "LocalJumpError") != null);
}

test "Kernel#tap validates arg count" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const bad = evalCodeWithOutput("Object.new.tap(1) { }", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "ArgumentError") != null);
}

test "Kernel#method returns callable bound method wrapper" {
    const result = try evalCode(
        \\class KernelMethodBoundTarget
        \\  def greet(name)
        \\    "hi #{name}"
        \\  end
        \\end
        \\obj = KernelMethodBoundTarget.new
        \\m = obj.method(:greet)
        \\[m.call("bob"), m.to_proc.call("kim")]
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqualStrings("hi bob", result.toArrayObject().elements.items[0].toStringObject().str);
    try std.testing.expectEqualStrings("hi kim", result.toArrayObject().elements.items[1].toStringObject().str);
}

test "Kernel#method owner returns the defining class" {
    const result = try evalCode("42.method(:zero?).owner == Integer");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());
}

test "Kernel#method raises NameError for missing method" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const bad = evalCodeWithOutput("Object.new.method(:does_not_exist)", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "NameError") != null);
}

test "Hash#default= sets value returned for missing keys" {
    const result = try evalCode(
        \\h = {}
        \\h.default = "x"
        \\[h[:missing], h.default]
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqualStrings("x", result.toArrayObject().elements.items[0].toStringObject().str);
    try std.testing.expectEqualStrings("x", result.toArrayObject().elements.items[1].toStringObject().str);
}

test "Hash#default_proc= drives missing-key lookup and getter" {
    const result = try evalCode(
        \\h = {}
        \\h.default_proc = ->(_hash, key) { "miss:#{key}" }
        \\[h[:abc], h.default_proc.nil?, h.default(:xyz)]
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqualStrings("miss:abc", result.toArrayObject().elements.items[0].toStringObject().str);
    try std.testing.expectEqual(false, result.toArrayObject().elements.items[1].toBool());
    try std.testing.expectEqualStrings("miss:xyz", result.toArrayObject().elements.items[2].toStringObject().str);
}

test "Hash#default_proc= rejects non-Proc values" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const bad = evalCodeWithOutput("h = {}; h.default_proc = 1", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "TypeError") != null);
}
