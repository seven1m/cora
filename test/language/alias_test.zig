const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "alias keyword in a class" {
    const result = try evalCode(
        \\class Foo
        \\  def greet
        \\    "hello"
        \\  end
        \\  alias hi greet
        \\end
        \\Foo.new.hi
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "hello", result.toStringObject().str);
}

test "alias keyword preserves original method" {
    const result = try evalCode(
        \\class Foo
        \\  def greet
        \\    "hello"
        \\  end
        \\  alias hi greet
        \\end
        \\Foo.new.greet
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "hello", result.toStringObject().str);
}

test "alias is independent of original method redefinition" {
    const result = try evalCode(
        \\class Foo
        \\  def greet
        \\    "hello"
        \\  end
        \\  alias hi greet
        \\  def greet
        \\    "hey"
        \\  end
        \\end
        \\Foo.new.hi
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "hello", result.toStringObject().str);
}

test "alias at top-level" {
    const result = try evalCode(
        \\def greet
        \\  "hello"
        \\end
        \\alias hi greet
        \\hi
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "hello", result.toStringObject().str);
}

test "alias_method with symbol args" {
    const result = try evalCode(
        \\class Bar
        \\  def greet
        \\    "hello"
        \\  end
        \\  alias_method :hi, :greet
        \\end
        \\Bar.new.hi
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "hello", result.toStringObject().str);
}

test "alias_method with string args" {
    const result = try evalCode(
        \\class Bar
        \\  def greet
        \\    "hello"
        \\  end
        \\  alias_method "hi", "greet"
        \\end
        \\Bar.new.hi
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "hello", result.toStringObject().str);
}

test "alias_method returns new name as symbol" {
    const result = try evalCode(
        \\class Baz
        \\  def greet
        \\    "hello"
        \\  end
        \\end
        \\Baz.alias_method(:hi, :greet)
    );
    try std.testing.expect(result.isSymbol());
    try std.testing.expectEqualSlices(u8, "hi", result.toSymbolObject().name);
}

test "inherited alias preserves the original owner for super" {
    const result = try evalCode(
        \\class AliasSuperBase
        \\  def value
        \\    [:base]
        \\  end
        \\end
        \\class AliasSuperMiddle < AliasSuperBase
        \\  def value
        \\    [:middle, super]
        \\  end
        \\end
        \\class AliasSuperChild < AliasSuperMiddle
        \\  alias_method :aliased_value, :value
        \\end
        \\AliasSuperChild.new.aliased_value
    );
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 2), items.len);
    try std.testing.expectEqualStrings("middle", items[0].toSymbolObject().name);
    try std.testing.expectEqualStrings("base", items[1].toArrayObject().elements.items[0].toSymbolObject().name);
}

test "alias_method coerces names via to_str" {
    const result = try evalCode(
        \\class Baz
        \\  def greet
        \\    "hello"
        \\  end
        \\end
        \\new_name = Object.new
        \\old_name = Object.new
        \\def new_name.to_str
        \\  "hi"
        \\end
        \\def old_name.to_str
        \\  "greet"
        \\end
        \\Baz.alias_method(new_name, old_name)
        \\Baz.new.hi
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "hello", result.toStringObject().str);
}

test "alias undefined method raises NameError" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\class Foo
        \\  alias hi greet
        \\end
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "NameError") != null);
}

test "alias_method undefined method raises NameError" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\class Foo
        \\  alias_method :hi, :greet
        \\end
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "NameError") != null);
}

test "alias can target inherited private methods in class_eval" {
    const result = try evalCode(
        \\kernel = Kernel.dup
        \\kernel.class_eval do
        \\  alias __raise__ raise
        \\end
        \\kernel.private_instance_methods(false).include?(:__raise__)
    );
    try std.testing.expect(result.isTrue());
}

test "alias in a module can target Object instance methods" {
    const result = try evalCode(
        \\module Introspection
        \\  alias responds_without_extension? respond_to?
        \\end
        \\class Subject
        \\  include Introspection
        \\end
        \\Subject.new.responds_without_extension?(:to_s)
    );
    try std.testing.expect(result.isTrue());
}

test "alias global variable copies value" {
    const result = try evalCode(
        \\$bar = 42
        \\alias $foo $bar
        \\$foo
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
}

test "alias global variable returns nil" {
    const result = try evalCode(
        \\alias $foo $bar
    );
    try std.testing.expect(result.isNil());
}

test "alias undefined global variable sets nil" {
    const result = try evalCode(
        \\alias $foo $undefined_xyz
        \\$foo
    );
    try std.testing.expect(result.isNil());
}

test "alias global variable with backref name" {
    const result = try evalCode(
        \\"waterbuffalo" =~ /buff/
        \\alias $MATCH $&
        \\$MATCH
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "buff", result.toStringObject().str);
}

test "alias global variable shares the slot" {
    const result = try evalCode(
        \\$bar = 42
        \\alias $foo $bar
        \\$bar = 100
        \\$foo
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 100), result.toInteger());
}

test "alias global variable updates original on write" {
    const result = try evalCode(
        \\$bar = 42
        \\alias $foo $bar
        \\$foo = 999
        \\$bar
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 999), result.toInteger());
}

test "alias global variable re-alias breaks prior alias chain" {
    // Matches MRI: re-aliasing $b to $c does not update $a, which still
    // references the old $b slot (nil here).
    const result = try evalCode(
        \\$c = 1
        \\alias $a $b
        \\alias $b $c
        \\$c = 99
        \\$a
    );
    try std.testing.expect(result.isNil());
}

test "alias global variable self alias is a no-op" {
    const result = try evalCode(
        \\$a = 7
        \\alias $a $a
        \\$a
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 7), result.toInteger());
}

test "alias keyword uses the instance_eval definition owner" {
    const result = try evalCode(
        \\string_object = Object.new
        \\string_object.instance_eval("def string_source; :string; end; alias string_copy string_source")
        \\block_object = Object.new
        \\block_object.instance_eval do
        \\  def block_source; :block; end
        \\  alias block_copy block_source
        \\end
        \\[string_object.string_copy, block_object.block_copy,
        \\ Object.method_defined?(:string_copy), Object.method_defined?(:block_copy)]
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqualStrings("string", values[0].toSymbolObject().name);
    try std.testing.expectEqualStrings("block", values[1].toSymbolObject().name);
    try std.testing.expect(values[2].isFalse() and values[3].isFalse());
}

test "top-level alias keyword finds inherited methods" {
    const result = try evalCode(
        \\alias inherited_string_copy to_s
        \\object = Object.new
        \\[object.inherited_string_copy == object.to_s, Object.instance_method(:inherited_string_copy).owner == Object]
    );
    for (result.toArrayObject().elements.items) |value| try std.testing.expect(value.isTrue());
}

test "undef keyword shares the lexical method definition owner" {
    const result = try evalCode(
        \\def removable_top_level_method; end
        \\undef removable_top_level_method
        \\class LexicalUndefOwner
        \\  def target; end
        \\  def remove_target; undef target; end
        \\end
        \\LexicalUndefOwner.new.remove_target
        \\[Object.method_defined?(:removable_top_level_method), LexicalUndefOwner.method_defined?(:target)]
    );
    for (result.toArrayObject().elements.items) |value| try std.testing.expect(value.isFalse());
}

test "undef keyword and undef_method reject an existing undefined barrier" {
    const result = try evalCode(
        \\class RepeatedUndefOwner
        \\  def target; end
        \\  undef target
        \\end
        \\keyword = begin
        \\  class RepeatedUndefOwner; undef target; end
        \\  false
        \\rescue NameError
        \\  true
        \\end
        \\method = begin
        \\  RepeatedUndefOwner.send(:undef_method, :target)
        \\  false
        \\rescue NameError
        \\  true
        \\end
        \\[keyword, method]
    );
    for (result.toArrayObject().elements.items) |value| try std.testing.expect(value.isTrue());
}
