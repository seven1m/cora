const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

// --- Enumerator.new with generator ---

test "Enumerator.new with yielder" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\e = Enumerator.new { |y| y << 1; y << 2; y << 3 }
        \\e.each { |v| puts v }
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("1\n2\n3\n", result.stdout);
}

test "Enumerator.new with next" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\e = Enumerator.new { |y| y << "a"; y << "b"; y << "c" }
        \\puts e.next
        \\puts e.next
        \\puts e.next
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("a\nb\nc\n", result.stdout);
}

test "Enumerator.new next raises StopIteration" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\e = Enumerator.new { |y| y << 1 }
        \\puts e.next
        \\begin
        \\  e.next
        \\  puts "should not reach"
        \\rescue StopIteration
        \\  puts "stopped"
        \\end
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("1\nstopped\n", result.stdout);
}

// --- Method-based enumerator (Array#each without block) ---

test "Array#each without block returns Enumerator" {
    const result = try evalCode("[1, 2, 3].each");
    try std.testing.expect(result.data == .enumerator);
}

test "Array#each enumerator round-trip" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\[1, 2, 3].each.each { |v| puts v }
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("1\n2\n3\n", result.stdout);
}

test "Array#each enumerator next" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\e = [10, 20, 30].each
        \\puts e.next
        \\puts e.next
        \\puts e.next
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("10\n20\n30\n", result.stdout);
}

test "Array#map without block returns Enumerator" {
    const result = try evalCode("[1, 2, 3].map");
    try std.testing.expect(result.data == .enumerator);
}

test "Array#each_with_index without block returns Enumerator" {
    const result = try evalCode("[1, 2, 3].each_with_index");
    try std.testing.expect(result.data == .enumerator);
}

// --- Peek ---

test "Enumerator#peek" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\e = [1, 2, 3].each
        \\puts e.peek
        \\puts e.peek
        \\puts e.next
        \\puts e.peek
        \\puts e.next
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("1\n1\n1\n2\n2\n", result.stdout);
}

// --- Rewind ---

test "Enumerator#rewind" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\e = [1, 2, 3].each
        \\puts e.next
        \\puts e.next
        \\e.rewind
        \\puts e.next
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("1\n2\n1\n", result.stdout);
}

// --- Yielder chaining ---

test "Yielder << chaining" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\e = Enumerator.new { |y| y << 1 << 2 << 3 }
        \\e.each { |v| puts v }
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("1\n2\n3\n", result.stdout);
}

// --- Hash#each without block ---

test "Hash#each without block returns Enumerator" {
    const result = try evalCode("{a: 1}.each");
    try std.testing.expect(result.data == .enumerator);
}

// --- Integer#times without block ---

test "Integer#times without block returns Enumerator" {
    const result = try evalCode("3.times");
    try std.testing.expect(result.data == .enumerator);
}

test "Integer#times enumerator next" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\e = 3.times
        \\puts e.next
        \\puts e.next
        \\puts e.next
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("0\n1\n2\n", result.stdout);
}

// --- Enumerator#each without block returns self ---

test "Enumerator#each without block returns self" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\e = [1, 2, 3].each
        \\e2 = e.each
        \\puts e2.next
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("1\n", result.stdout);
}

// --- Inspect ---

test "Enumerator#inspect for method-based" {
    const result = try evalCode("[1, 2, 3].each.inspect");
    try std.testing.expect(result.data == .string);
    const str = result.data.string.str;
    try std.testing.expect(std.mem.indexOf(u8, str, "Enumerator") != null);
    try std.testing.expect(std.mem.indexOf(u8, str, "each") != null);
}

// --- StopIteration exception hierarchy ---

test "StopIteration is a kind of IndexError" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\begin
        \\  raise StopIteration
        \\rescue IndexError
        \\  puts "caught"
        \\end
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("caught\n", result.stdout);
}

// --- Array#each round-trip ---

test "Array#each enumerator round-trip with each" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\[10, 20, 30].each.each { |v| puts v }
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("10\n20\n30\n", result.stdout);
}

// --- Infinite enumerator ---

test "Enumerator infinite generator with next" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\e = Enumerator.new { |y| i = 0; loop { i = i + 1; y << i } }
        \\puts e.next
        \\puts e.next
        \\puts e.next
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("1\n2\n3\n", result.stdout);
}

// --- Integer#upto without block ---

test "Integer#upto without block returns Enumerator" {
    const result = try evalCode("1.upto(5)");
    try std.testing.expect(result.data == .enumerator);
}

test "Integer#upto enumerator next" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\e = 1.upto(3)
        \\puts e.next
        \\puts e.next
        \\puts e.next
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("1\n2\n3\n", result.stdout);
}
