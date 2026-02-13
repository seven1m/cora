const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "p with no arguments" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;

    const result = evalCodeWithOutput("p", &stdout_buf, &stderr_buf);
    try std.testing.expect(result.value.data == .nil);
    try std.testing.expectEqualStrings("\n", result.stdout);
}

test "p with single integer" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;

    const result = evalCodeWithOutput("p 42", &stdout_buf, &stderr_buf);
    try std.testing.expect(result.value.data == .integer);
    try std.testing.expectEqual(@as(i64, 42), result.value.data.integer);
    try std.testing.expectEqualStrings("42\n", result.stdout);
}

test "p with single string" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;

    const result = evalCodeWithOutput("p \"hello\"", &stdout_buf, &stderr_buf);
    try std.testing.expect(result.value.data == .string);
    try std.testing.expectEqualSlices(u8, "hello", result.value.data.string.str);
    try std.testing.expectEqualStrings("\"hello\"\n", result.stdout);
}

test "p with multiple integers" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;

    const result = evalCodeWithOutput("p 1, 2, 3", &stdout_buf, &stderr_buf);
    try std.testing.expect(result.value.data == .array);
    try std.testing.expectEqual(@as(usize, 3), result.value.data.array.elements.items.len);
    try std.testing.expectEqualStrings("1\n2\n3\n", result.stdout);
}

test "p with mixed types" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;

    const result = evalCodeWithOutput("p 42, \"hello\", :foo", &stdout_buf, &stderr_buf);
    try std.testing.expect(result.value.data == .array);
    try std.testing.expectEqual(@as(usize, 3), result.value.data.array.elements.items.len);
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
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(false, result.data.boolean);
}

test "Kernel#freeze returns receiver and marks String frozen" {
    const result = try evalCode("s = \"hello\"; s.freeze.object_id == s.object_id && s.frozen?");
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(true, result.data.boolean);
}

test "Kernel#freeze marks Hash frozen and prevents mutation" {
    const frozen_result = try evalCode("h = {}; h.freeze; h.frozen?");
    try std.testing.expect(frozen_result.data == .boolean);
    try std.testing.expectEqual(true, frozen_result.data.boolean);

    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const mutation = evalCodeWithOutput("h = {}; h.freeze; h[:x] = 1", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, mutation.err.?);
}

test "Kernel#freeze on Integer is a no-op and remains frozen" {
    const result = try evalCode("i = 42; i.freeze.object_id == i.object_id && i.frozen?");
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(true, result.data.boolean);
}

test "Kernel#instance_of? returns true for exact class and false for ancestor/module" {
    var result = try evalCode("\"\".instance_of?(String)");
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(true, result.data.boolean);

    result = try evalCode(
        \\class A
        \\end
        \\class B < A
        \\end
        \\B.new.instance_of?(A)
    );
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(false, result.data.boolean);

    result = try evalCode(
        \\module M
        \\end
        \\class C
        \\  include M
        \\end
        \\C.new.instance_of?(M)
    );
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(false, result.data.boolean);
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
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(true, result.data.array.elements.items[0].data.boolean);
    try std.testing.expectEqual(true, result.data.array.elements.items[1].data.boolean);
    try std.testing.expectEqual(false, result.data.array.elements.items[2].data.boolean);

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
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(false, result.data.array.elements.items[0].data.boolean);
    try std.testing.expectEqual(false, result.data.array.elements.items[1].data.boolean);
    try std.testing.expectEqual(false, result.data.array.elements.items[2].data.boolean);
    try std.testing.expectEqual(false, result.data.array.elements.items[3].data.boolean);
    try std.testing.expectEqual(true, result.data.array.elements.items[4].data.boolean);
    try std.testing.expectEqual(true, result.data.array.elements.items[5].data.boolean);
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
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(true, result.data.boolean);
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
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, 42), result.data.integer);
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
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, 9), result.data.integer);

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
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(usize, 2), result.data.array.elements.items.len);
    try std.testing.expect(result.data.array.elements.items[0].data == .class);
    try std.testing.expect(result.data.array.elements.items[1].data == .class);
    try std.testing.expect(
        result.data.array.elements.items[0].data.class == result.data.array.elements.items[1].data.class,
    );
}

test "Kernel#singleton_class returns NilClass/TrueClass/FalseClass for immediates" {
    var result = try evalCode("nil.singleton_class");
    try std.testing.expect(result.data == .class);
    try std.testing.expectEqualStrings("NilClass", result.data.class.module.name.name);

    result = try evalCode("true.singleton_class");
    try std.testing.expect(result.data == .class);
    try std.testing.expectEqualStrings("TrueClass", result.data.class.module.name.name);

    result = try evalCode("false.singleton_class");
    try std.testing.expect(result.data == .class);
    try std.testing.expectEqualStrings("FalseClass", result.data.class.module.name.name);
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
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(true, result.data.boolean);
}
