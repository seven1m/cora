const std = @import("std");
const c = @cImport(@cInclude("prism.h"));

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Prism VM\n", .{});

    const ruby_code = "puts \"Hello from Prism!\"";

    var parser: c.pm_parser_t = undefined;
    c.pm_parser_init(&parser, ruby_code.ptr, ruby_code.len, null);
    defer c.pm_parser_free(&parser);

    const ast = c.pm_parse(&parser);
    if (ast == null) {
        std.debug.print("Parse error\n", .{});
        return;
    }
    defer c.pm_node_destroy(null, ast);

    std.debug.print("Successfully parsed Ruby code\n\n", .{});

    var output_buffer: c.pm_buffer_t = undefined;
    if (!c.pm_buffer_init(&output_buffer)) {
        std.debug.print("Failed to initialize output buffer\n", .{});
        return;
    }
    defer c.pm_buffer_free(&output_buffer);

    c.pm_prettyprint(&output_buffer, &parser, ast);

    const output_str = c.pm_buffer_value(&output_buffer);
    const output_len = c.pm_buffer_length(&output_buffer);

    std.debug.print("AST:\n{s}\n", .{output_str[0..output_len]});

    _ = allocator;
}
