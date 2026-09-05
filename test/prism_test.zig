const std = @import("std");
const Parser = @import("cora").prism.Parser;

test "Parser.init provides ProgramNode AST for invalid code" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const invalid_code = "def foo\n  (\n";

    var parser = try Parser.init(allocator, invalid_code, null);
    defer parser.deinit();

    // ast is never null
    _ = parser.ast;
}

test "Parser.init provides ProgramNode AST for valid code" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const valid_code = "puts 'hello'";

    var parser = try Parser.init(allocator, valid_code, null);
    defer parser.deinit();

    _ = parser.ast;
}

test "Parser.lineColumn uses parsed newline offsets" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = "first\n  second\nthird";
    var parser = try Parser.init(allocator, source, null);
    defer parser.deinit();

    try std.testing.expectEqual(Parser.LineColumn{ .line = 1, .column = 0 }, parser.lineColumn(source.ptr));
    try std.testing.expectEqual(Parser.LineColumn{ .line = 2, .column = 2 }, parser.lineColumn(source.ptr + 8));
    try std.testing.expectEqual(Parser.LineColumn{ .line = 3, .column = 0 }, parser.lineColumn(source.ptr + 15));
}
