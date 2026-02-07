const std = @import("std");
const Parser = @import("cora").prism.Parser;

test "Parser.init provides ProgramNode AST for invalid code" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const invalid_code = "def foo\n  (\n";

    var parser = try Parser.init(allocator, invalid_code, null);
    defer parser.deinit();

    // ast is never null
    _ = parser.ast;
}

test "Parser.init provides ProgramNode AST for valid code" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const valid_code = "puts 'hello'";

    var parser = try Parser.init(allocator, valid_code, null);
    defer parser.deinit();

    _ = parser.ast;
}
