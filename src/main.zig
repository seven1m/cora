const std = @import("std");
pub const prism = @cImport(@cInclude("prism.h"));
pub const Value = @import("value.zig").Value;
const Interpreter = @import("interpreter.zig").Interpreter;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var ruby_code: ?[]const u8 = null;
    var print_ast = false;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-e")) {
            if (i + 1 < args.len) {
                ruby_code = args[i + 1];
                i += 1;
            } else {
                std.debug.print("Error: -e requires an argument\n", .{});
                return;
            }
        } else if (std.mem.eql(u8, args[i], "--ast")) {
            print_ast = true;
        }
    }

    if (ruby_code == null) {
        std.debug.print("Usage: clara [--ast] -e <ruby code>\n", .{});
        return;
    }

    const code = ruby_code.?;
    var parser: prism.pm_parser_t = undefined;
    prism.pm_parser_init(&parser, code.ptr, code.len, null);
    defer prism.pm_parser_free(&parser);

    const ast = prism.pm_parse(&parser);
    if (ast == null) {
        std.debug.print("Parse error\n", .{});
        return;
    }
    defer prism.pm_node_destroy(null, ast);

    if (print_ast) {
        var buffer: prism.pm_buffer_t = undefined;
        _ = prism.pm_buffer_init(&buffer);
        defer prism.pm_buffer_free(&buffer);

        prism.pm_prettyprint(&buffer, &parser, ast);

        const output = buffer.value[0..buffer.length];
        std.debug.print("{s}\n", .{output});
        return;
    }

    var interpreter = Interpreter.init(allocator, &parser);
    defer interpreter.deinit();
    _ = interpreter.eval(ast);
}
