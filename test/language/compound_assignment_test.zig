const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "local ||= initializes undefined local" {
    const result = try evalCode(
        \\a ||= 1
        \\a
    );
    try std.testing.expectEqual(@as(i64, 1), result.toInteger());
}

test "local &&= on undefined local returns nil and keeps nil" {
    const result = try evalCode(
        \\a &&= 1
        \\a
    );
    try std.testing.expect(result.isNil());
}

test "local compound assignment short-circuits rhs" {
    var result = try evalCode(
        \\x = nil
        \\y = 0
        \\x &&= (y = 1)
        \\y
    );
    try std.testing.expectEqual(@as(i64, 0), result.toInteger());

    result = try evalCode(
        \\x = false
        \\y = 0
        \\x ||= (y = 1)
        \\y
    );
    try std.testing.expectEqual(@as(i64, 1), result.toInteger());
}

test "local compound assignment updates outer scope locals" {
    var result = try evalCode(
        \\x = 1
        \\f = -> { x &&= 2 }
        \\f.call
        \\x
    );
    try std.testing.expectEqual(@as(i64, 2), result.toInteger());

    result = try evalCode(
        \\x = nil
        \\f = -> { x ||= 3 }
        \\f.call
        \\x
    );
    try std.testing.expectEqual(@as(i64, 3), result.toInteger());
}

test "local operator assignment updates local variable" {
    const result = try evalCode(
        \\x = 1
        \\x += 2
        \\x
    );
    try std.testing.expectEqual(@as(i64, 3), result.toInteger());
}

test "local operator assignment updates captured outer local" {
    const result = try evalCode(
        \\x = 10
        \\f = -> { x += 5 }
        \\f.call
        \\x
    );
    try std.testing.expectEqual(@as(i64, 15), result.toInteger());
}

test "index operator assignment updates array element and returns assigned value" {
    const result = try evalCode(
        \\a = [10, 20, 30]
        \\x = (a[1] += 5)
        \\[x, a[1]]
    );

    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 2), result.toArrayObject().elements.items.len);
    try std.testing.expectEqual(@as(i64, 25), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 25), result.toArrayObject().elements.items[1].toInteger());
}

test "index operator assignment evaluates index expression once" {
    const result = try evalCode(
        \\a = [1, 2, 3]
        \\i = 0
        \\a[(i = i + 1)] += 10
        \\i
    );

    try std.testing.expectEqual(@as(i64, 1), result.toInteger());
}

test "index operator assignment evaluates receiver expression once" {
    const result = try evalCode(
        \\$counter = 0
        \\def make_array
        \\  $counter = $counter + 1
        \\  [1, 2, 3]
        \\end
        \\make_array[0] += 7
        \\$counter
    );

    try std.testing.expectEqual(@as(i64, 1), result.toInteger());
}

test "index operator assignment supports splatted index arguments" {
    const result = try evalCode(
        \\a = [10, 20, 30]
        \\idx = [1]
        \\a[*idx] += 7
        \\a[1]
    );
    try std.testing.expectEqual(@as(i64, 27), result.toInteger());
}

test "index ||= caches existing value and evaluates rhs once" {
    const result = try evalCode(
        \\$builds = 0
        \\
        \\class Foo
        \\  def initialize
        \\    @cache = {}
        \\  end
        \\
        \\  def fetch(key)
        \\    @cache[key] ||= begin
        \\      $builds += 1
        \\      key.upcase
        \\    end
        \\  end
        \\end
        \\
        \\foo = Foo.new
        \\[foo.fetch("a"), foo.fetch("a"), $builds]
    );

    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 3), result.toArrayObject().elements.items.len);
    try std.testing.expectEqualStrings("A", result.toArrayObject().elements.items[0].toStringObject().str);
    try std.testing.expectEqualStrings("A", result.toArrayObject().elements.items[1].toStringObject().str);
    try std.testing.expectEqual(@as(i64, 1), result.toArrayObject().elements.items[2].toInteger());
}

test "index &&= short-circuits falsey values without evaluating rhs" {
    const result = try evalCode(
        \\$builds = 0
        \\a = [nil]
        \\x = (a[0] &&= begin
        \\  $builds += 1
        \\  7
        \\end)
        \\[x, a[0], $builds]
    );

    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 3), result.toArrayObject().elements.items.len);
    try std.testing.expect(result.toArrayObject().elements.items[0].isNil());
    try std.testing.expect(result.toArrayObject().elements.items[1].isNil());
    try std.testing.expectEqual(@as(i64, 0), result.toArrayObject().elements.items[2].toInteger());
}

test "index &&= updates truthy values and evaluates receiver once" {
    const result = try evalCode(
        \\$calls = 0
        \\def make_array
        \\  $calls += 1
        \\  [1]
        \\end
        \\x = (make_array[0] &&= 9)
        \\[x, $calls]
    );

    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 2), result.toArrayObject().elements.items.len);
    try std.testing.expectEqual(@as(i64, 9), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 1), result.toArrayObject().elements.items[1].toInteger());
}

test "global compound assignment" {
    var result = try evalCode(
        \\$g = nil
        \\$g ||= 9
        \\$g
    );
    try std.testing.expectEqual(@as(i64, 9), result.toInteger());

    result = try evalCode(
        \\$h = false
        \\$h &&= 7
        \\$h
    );
    try std.testing.expect(result.isBool() and !result.toBool());

    result = try evalCode(
        \\$i = 1
        \\$i += 2
        \\$i
    );
    try std.testing.expectEqual(@as(i64, 3), result.toInteger());
}

test "instance variable compound assignment" {
    var result = try evalCode(
        \\class Foo
        \\  def run
        \\    @x ||= 10
        \\  end
        \\end
        \\Foo.new.run
    );
    try std.testing.expectEqual(@as(i64, 10), result.toInteger());

    result = try evalCode(
        \\class Bar
        \\  def run
        \\    @y = nil
        \\    @y &&= 5
        \\  end
        \\end
        \\Bar.new.run
    );
    try std.testing.expect(result.isNil());
}

test "call ||= assigns through getter/setter and evaluates receiver once" {
    const result = try evalCode(
        \\$calls = 0
        \\$last = nil
        \\class Foo
        \\  attr_accessor :bar
        \\end
        \\def make_foo
        \\  $calls += 1
        \\  $last = Foo.new
        \\end
        \\x = (make_foo.bar ||= true)
        \\[x, $last.bar, $calls]
    );

    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 3), result.toArrayObject().elements.items.len);
    try std.testing.expect(result.toArrayObject().elements.items[0].isBool() and result.toArrayObject().elements.items[0].toBool());
    try std.testing.expect(result.toArrayObject().elements.items[1].isBool() and result.toArrayObject().elements.items[1].toBool());
    try std.testing.expectEqual(@as(i64, 1), result.toArrayObject().elements.items[2].toInteger());
}

test "call &&= short-circuits falsey getter result" {
    const result = try evalCode(
        \\class Foo
        \\  attr_accessor :bar
        \\end
        \\foo = Foo.new
        \\x = (foo.bar &&= true)
        \\[x, foo.bar]
    );

    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 2), result.toArrayObject().elements.items.len);
    try std.testing.expect(result.toArrayObject().elements.items[0].isNil());
    try std.testing.expect(result.toArrayObject().elements.items[1].isNil());
}

test "call operator assignment assigns through getter/setter and evaluates receiver once" {
    const result = try evalCode(
        \\$calls = 0
        \\$last = nil
        \\class Scanner
        \\  attr_accessor :pos
        \\end
        \\def make_scanner
        \\  $calls += 1
        \\  $last = Scanner.new
        \\  $last.pos = 5
        \\  $last
        \\end
        \\x = (make_scanner.pos -= 1)
        \\[x, $last.pos, $calls]
    );

    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 3), result.toArrayObject().elements.items.len);
    try std.testing.expectEqual(@as(i64, 4), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 4), result.toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 1), result.toArrayObject().elements.items[2].toInteger());
}

test "constant ||= initializes when missing" {
    const result = try evalCode(
        \\X ||= 1
        \\X
    );
    try std.testing.expectEqual(@as(i64, 1), result.toInteger());
}

test "constant ||= assigns when existing constant is falsey" {
    const result = try evalCode(
        \\Y = false
        \\Y ||= 2
        \\Y
    );
    try std.testing.expectEqual(@as(i64, 2), result.toInteger());
}

test "constant path ||= initializes missing constant and skips RHS when truthy" {
    const result = try evalCode(
        \\class Foo; end
        \\calls = 0
        \\first = (Foo::Bar ||= (calls += 1))
        \\second = (Foo::Bar ||= (calls += 1))
        \\[first, second, Foo::Bar, calls]
    );
    const elements = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 4), elements.len);
    for (elements) |element| try std.testing.expectEqual(@as(i64, 1), element.toInteger());
}

test "constant path ||= evaluates parent once and replaces falsey value" {
    const result = try evalCode(
        \\class Foo; Bar = false; end
        \\calls = 0
        \\def parent
        \\  $parent_calls += 1
        \\  Foo
        \\end
        \\$parent_calls = 0
        \\value = (parent::Bar ||= 3)
        \\[value, Foo::Bar, $parent_calls]
    );
    const elements = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 3), elements.len);
    try std.testing.expectEqual(@as(i64, 3), elements[0].toInteger());
    try std.testing.expectEqual(@as(i64, 3), elements[1].toInteger());
    try std.testing.expectEqual(@as(i64, 1), elements[2].toInteger());
}

test "constant path ||= loads autoload before evaluating RHS" {
    const result = try evalCode(
        \\class AutoloadPath; end
        \\AutoloadPath.autoload(:Value, File.expand_path("test/support/autoload_constant_path", Dir.pwd))
        \\$assigned = false
        \\value = (AutoloadPath::Value ||= ($assigned = true))
        \\[value, AutoloadPath::Value, $assigned]
    );
    const elements = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 3), elements.len);
    try std.testing.expectEqual(@as(i64, 7), elements[0].toInteger());
    try std.testing.expectEqual(@as(i64, 7), elements[1].toInteger());
    try std.testing.expect(elements[2].isFalse());
}

test "constant path ||= loads an inherited autoload" {
    const result = try evalCode(
        \\module AncestorAutoload; end
        \\AncestorAutoload.autoload(:Loaded, File.expand_path("test/support/autoload_ancestor_constant", Dir.pwd))
        \\class AutoloadChild
        \\  include AncestorAutoload
        \\end
        \\$assigned = false
        \\value = (AutoloadChild::Loaded ||= ($assigned = true))
        \\[value::Value, $assigned]
    );
    const elements = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 2), elements.len);
    try std.testing.expectEqual(@as(i64, 23), elements[0].toInteger());
    try std.testing.expect(elements[1].isFalse());
}

test "constant path ||= raises when autoload does not define the constant" {
    const result = try evalCode(
        \\class AutoloadMissing; end
        \\AutoloadMissing.autoload(:Value, File.expand_path("test/support/autoload_ancestor_constant", Dir.pwd))
        \\$assigned = false
        \\$raised = false
        \\begin
        \\  AutoloadMissing::Value ||= ($assigned = true)
        \\rescue NameError
        \\  $raised = true
        \\end
        \\[$raised, $assigned, AutoloadMissing.const_defined?(:Value, false)]
    );
    const elements = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 3), elements.len);
    try std.testing.expect(elements[0].isTrue());
    try std.testing.expect(elements[1].isFalse());
    try std.testing.expect(elements[2].isFalse());
}

test "constant &&= raises NameError when constant is missing" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        "Z &&= 1",
        &stdout_buf,
        &stderr_buf,
    );

    try std.testing.expectEqual(@as(?anyerror, error.UnhandledException), result.err);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "NameError") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "uninitialized constant Z") != null);
}
