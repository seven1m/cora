const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Begin/rescue catches exception" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\begin
        \\  raise "error"
        \\rescue
        \\  puts "caught"
        \\end
    , &stdout_buf, &stderr_buf);

    // Rescue should catch the exception, so no error is raised
    try std.testing.expect(result.err == null);
    try std.testing.expect(result.value.isNil());

    try std.testing.expectEqualSlices(u8, "caught\n", result.stdout);
}

test "Begin/rescue returns value from rescue" {
    const result = try evalCode(
        \\begin
        \\  raise "error"
        \\rescue
        \\  42
        \\end
    );
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
}

test "Begin/rescue with no exception executes protected code" {
    const result = try evalCode(
        \\begin
        \\  10 + 5
        \\rescue
        \\  0
        \\end
    );
    try std.testing.expectEqual(@as(i64, 15), result.toInteger());
}

test "Rescue with variable binding - capture exception" {
    const result = try evalCode(
        \\begin
        \\  raise RuntimeError, "my message"
        \\rescue => e
        \\  42
        \\end
    );
    // For now, just verify rescue clause executes
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
}

test "Nested begin/rescue" {
    const result = try evalCode(
        \\begin
        \\  begin
        \\    raise "inner"
        \\  rescue
        \\    1
        \\  end
        \\rescue
        \\  2
        \\end
    );
    try std.testing.expectEqual(@as(i64, 1), result.toInteger());
}

test "Exception class hierarchy - StandardError caught by bare rescue" {
    const result = try evalCode(
        \\begin
        \\  raise ArgumentError, "arg error"
        \\rescue
        \\  1
        \\end
    );
    try std.testing.expectEqual(@as(i64, 1), result.toInteger());
}

test "Exception class hierarchy - TypeError caught by bare rescue" {
    const result = try evalCode(
        \\begin
        \\  raise TypeError, "type error"
        \\rescue
        \\  1
        \\end
    );
    try std.testing.expectEqual(@as(i64, 1), result.toInteger());
}

test "Exception in method call caught by outer rescue" {
    const result = try evalCode(
        \\def foo
        \\  raise "error in method"
        \\end
        \\begin
        \\  foo
        \\rescue
        \\  99
        \\end
    );
    try std.testing.expectEqual(@as(i64, 99), result.toInteger());
}

test "Basic rescue catches exception" {
    const result = try evalCode(
        \\begin
        \\  raise "error"
        \\rescue
        \\  42
        \\end
    );
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
}

test "Rescue with TypeError matches" {
    const result = try evalCode(
        \\begin
        \\  1 + "string"
        \\rescue TypeError
        \\  100
        \\end
    );
    try std.testing.expectEqual(@as(i64, 100), result.toInteger());
}

test "Rescue with ArgumentError matches" {
    const result = try evalCode(
        \\def foo
        \\  yield 1
        \\end
        \\begin
        \\  foo
        \\rescue ArgumentError
        \\  200
        \\end
    );
    try std.testing.expectEqual(@as(i64, 200), result.toInteger());
}

test "Rescue with NoMethodError matches" {
    const result = try evalCode(
        \\begin
        \\  1.nonexistent
        \\rescue NoMethodError
        \\  300
        \\end
    );
    try std.testing.expectEqual(@as(i64, 300), result.toInteger());
}

test "Multiple rescue clauses - correct type matched" {
    const result = try evalCode(
        \\begin
        \\  1 + "string"
        \\rescue ArgumentError
        \\  1
        \\rescue TypeError
        \\  2
        \\rescue NoMethodError
        \\  3
        \\end
    );
    try std.testing.expectEqual(@as(i64, 2), result.toInteger());
}

test "Multiple exception types in one rescue clause" {
    const result = try evalCode(
        \\begin
        \\  1 + "string"
        \\rescue ArgumentError, TypeError
        \\  99
        \\end
    );
    try std.testing.expectEqual(@as(i64, 99), result.toInteger());
}

test "Rescue with dynamic ivar exception type matches" {
    const result = try evalCode(
        \\@klass = TypeError
        \\begin
        \\  1 + "string"
        \\rescue @klass
        \\  123
        \\end
    );
    try std.testing.expectEqual(@as(i64, 123), result.toInteger());
}

test "Rescue with arbitrary expression exception type matches" {
    const result = try evalCode(
        \\begin
        \\  raise "boom"
        \\rescue (-> { StandardError }.call) => e
        \\  124
        \\end
    );
    try std.testing.expectEqual(@as(i64, 124), result.toInteger());
}

test "Rescue with module exception type matches" {
    const result = try evalCode(
        \\module Marker; end
        \\class CustomError < RuntimeError
        \\  include Marker
        \\end
        \\begin
        \\  raise CustomError, "boom"
        \\rescue Marker
        \\  125
        \\end
    );
    try std.testing.expectEqual(@as(i64, 125), result.toInteger());
}

test "Rescue with invalid exception type raises TypeError" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\@klass = 123
        \\begin
        \\  raise "boom"
        \\rescue @klass
        \\  0
        \\end
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "class or module required for rescue clause (TypeError)") != null);
}

test "Rescue with variable binding works" {
    const result = try evalCode(
        \\begin
        \\  raise "test message"
        \\rescue => e
        \\  77
        \\end
    );
    try std.testing.expectEqual(@as(i64, 77), result.toInteger());
}

test "Normal execution skips rescue clause" {
    const result = try evalCode(
        \\begin
        \\  10 + 5
        \\rescue
        \\  99
        \\end
    );
    try std.testing.expectEqual(@as(i64, 15), result.toInteger());
}

test "Rescue modifier - no exception returns main value" {
    const result = try evalCode("42 rescue 99");
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
}

test "Rescue modifier - exception returns rescue value" {
    const result = try evalCode(
        \\def fail
        \\  raise "error"
        \\end
        \\fail rescue 100
    );
    try std.testing.expectEqual(@as(i64, 100), result.toInteger());
}

test "Rescue modifier - in assignment" {
    const result = try evalCode(
        \\def risky
        \\  raise "danger"
        \\end
        \\x = risky rescue 50
        \\x
    );
    try std.testing.expectEqual(@as(i64, 50), result.toInteger());
}

test "All begin clauses together - normal completion" {
    const result = try evalCode(
        \\begin
        \\  10
        \\rescue
        \\  20
        \\else
        \\  30
        \\ensure
        \\  40
        \\end
    );
    try std.testing.expectEqual(@as(i64, 30), result.toInteger());
}

test "All begin clauses together - with exception" {
    const result = try evalCode(
        \\begin
        \\  raise "error"
        \\rescue
        \\  50
        \\else
        \\  60
        \\ensure
        \\  70
        \\end
    );
    try std.testing.expectEqual(@as(i64, 50), result.toInteger());
}
