const std = @import("std");
const prism = @import("prism.zig");
pub const Value = @import("value.zig").Value;
const Interpreter = @import("interpreter.zig").Interpreter;
const bdwgc = @import("bdwgc");

pub fn main() !void {
    bdwgc.init();
    defer bdwgc.deinit();

    var gpa = if (std.debug.runtime_safety)
        std.heap.DebugAllocator(.{}){}
    else
        std.heap.GeneralPurposeAllocator(.{}){};
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
    var parser = prism.Parser.init(allocator, code) catch {
        std.debug.print("Parse error\n", .{});
        return;
    };
    defer parser.deinit();

    if (print_ast) {
        const output = try parser.prettyPrint(allocator);
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
        return;
    }

    var interpreter = Interpreter.init(allocator, bdwgc.allocator, &parser);
    defer interpreter.deinit();

    const root_node = parser.root() catch unreachable;
    _ = interpreter.eval(root_node);
}
