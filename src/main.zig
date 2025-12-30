const std = @import("std");
const prism = @cImport(@cInclude("prism.h"));

const Value = struct {
    frozen: bool,
    data: union(enum) {
        string: []const u8,
        nil: void,
    },

    fn nil() Value {
        return Value{ .frozen = true, .data = .nil };
    }

    fn frozenString(str: []const u8) Value {
        return Value{ .frozen = true, .data = .{ .string = str } };
    }
};

const Interpreter = struct {
    allocator: std.mem.Allocator,
    parser: *prism.pm_parser_t,

    fn init(allocator: std.mem.Allocator, parser: *prism.pm_parser_t) @This() {
        return .{
            .allocator = allocator,
            .parser = parser,
        };
    }

    fn eval(self: *Interpreter, node: *prism.pm_node_t) Value {
        const node_type = node.type;

        if (node_type == prism.PM_PROGRAM_NODE) {
            const program = @as(*prism.pm_program_node_t, @ptrCast(node));
            if (program.statements != null) {
                return self.eval(@ptrCast(program.statements));
            }
            return Value.nil();
        }

        if (node_type == prism.PM_STATEMENTS_NODE) {
            const statements = @as(*prism.pm_statements_node_t, @ptrCast(node));
            var result: Value = Value.nil();
            var i: usize = 0;
            while (i < statements.body.size) : (i += 1) {
                result = self.eval(statements.body.nodes[i]);
            }
            return result;
        }

        if (node_type == prism.PM_STRING_NODE) {
            const string_node = @as(*prism.pm_string_node_t, @ptrCast(node));
            const str = string_node.unescaped;
            return Value.frozenString(str.source[0..str.length]);
        }

        if (node_type == prism.PM_CALL_NODE) {
            return self.evalCall(@ptrCast(node));
        }

        return Value.nil();
    }

    fn evalCall(self: *Interpreter, call_node: *prism.pm_call_node_t) Value {
        const constant = prism.pm_constant_pool_id_to_constant(&self.parser.constant_pool, call_node.name);
        if (constant == null) {
            return Value.nil();
        }

        const method_name = constant.*.start[0..constant.*.length];

        if (std.mem.eql(u8, method_name, "puts")) {
            return self.evalPuts(call_node);
        }

        return Value.nil();
    }

    fn evalPuts(self: *Interpreter, call_node: *prism.pm_call_node_t) Value {
        if (call_node.arguments == null) {
            std.debug.print("\n", .{});
            return Value.nil();
        }

        const args = @as(*prism.pm_arguments_node_t, @ptrCast(call_node.arguments));
        var i: usize = 0;
        while (i < args.arguments.size) : (i += 1) {
            const arg_value = self.eval(args.arguments.nodes[i]);
            switch (arg_value.data) {
                .string => |str| {
                    std.debug.print("{s}\n", .{str});
                },
                .nil => {
                    std.debug.print("\n", .{});
                },
            }
        }

        return Value.nil();
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Prism VM\n\n", .{});

    const ruby_code = "puts \"Hello from Prism!\"\nputs \"Line 2\"";

    std.debug.print("Ruby code:\n{s}\n\n", .{ruby_code});
    std.debug.print("Output:\n", .{});

    var parser: prism.pm_parser_t = undefined;
    prism.pm_parser_init(&parser, ruby_code.ptr, ruby_code.len, null);
    defer prism.pm_parser_free(&parser);

    const ast = prism.pm_parse(&parser);
    if (ast == null) {
        std.debug.print("Parse error\n", .{});
        return;
    }
    defer prism.pm_node_destroy(null, ast);

    var interpreter = Interpreter.init(allocator, &parser);
    _ = interpreter.eval(ast);
}
