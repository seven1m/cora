const std = @import("std");

const c = @cImport(@cInclude("prism.h"));

pub const CallNode = c.pm_call_node_t;
pub const ArgumentsNode = c.pm_arguments_node_t;
pub const DefNode = c.pm_def_node_t;

pub const Node = union(enum) {
    program: *c.pm_program_node_t,
    statements: *c.pm_statements_node_t,
    string: *c.pm_string_node_t,
    integer: *c.pm_integer_node_t,
    symbol: *c.pm_symbol_node_t,
    constant_read: *c.pm_constant_read_node_t,
    constant_write: *c.pm_constant_write_node_t,
    call: *c.pm_call_node_t,
    module: *c.pm_module_node,
    def: *c.pm_def_node_t,
};

/// Parser wraps Prism's parser and AST lifecycle
pub const Parser = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    internal: c.pm_parser_t,
    ast: ?*c.pm_node_t,

    /// Initialize parser with source code
    pub fn init(allocator: std.mem.Allocator, source: []const u8) !Parser {
        var parser: c.pm_parser_t = undefined;
        c.pm_parser_init(&parser, source.ptr, source.len, null);

        const ast = c.pm_parse(&parser);
        if (ast == null) {
            c.pm_parser_free(&parser);
            return error.ParseError;
        }

        return .{
            .allocator = allocator,
            .source = source,
            .internal = parser,
            .ast = ast,
        };
    }

    /// Free parser and AST
    pub fn deinit(self: *Parser) void {
        if (self.ast) |ast| {
            c.pm_node_destroy(null, ast);
        }
        c.pm_parser_free(&self.internal);
    }

    /// Get the root AST node, type-checked
    pub fn root(self: *Parser) !Node {
        const ast = self.ast orelse return error.RootNodeMissing;
        return self.asNode(ast);
    }

    /// Convert a raw C node pointer to a typed Node
    pub fn asNode(self: *Parser, raw: *c.pm_node_t) !Node {
        _ = self; // parser is needed for potential future use

        const node_type = raw.type;

        if (node_type == c.PM_PROGRAM_NODE) {
            return Node{ .program = @ptrCast(raw) };
        }

        if (node_type == c.PM_STATEMENTS_NODE) {
            return Node{ .statements = @ptrCast(raw) };
        }

        if (node_type == c.PM_STRING_NODE) {
            return Node{ .string = @ptrCast(raw) };
        }

        if (node_type == c.PM_INTEGER_NODE) {
            return Node{ .integer = @ptrCast(raw) };
        }

        if (node_type == c.PM_SYMBOL_NODE) {
            return Node{ .symbol = @ptrCast(raw) };
        }

        if (node_type == c.PM_CONSTANT_READ_NODE) {
            return Node{ .constant_read = @ptrCast(raw) };
        }

        if (node_type == c.PM_CONSTANT_WRITE_NODE) {
            return Node{ .constant_write = @ptrCast(raw) };
        }

        if (node_type == c.PM_CALL_NODE) {
            return Node{ .call = @ptrCast(raw) };
        }

        if (node_type == c.PM_MODULE_NODE) {
            return Node{ .module = @ptrCast(raw) };
        }

        if (node_type == c.PM_DEF_NODE) {
            return Node{ .def = @ptrCast(raw) };
        }

        return error.UnhandledNode;
    }

    pub fn getConstantName(self: *Parser, const_id: c.pm_constant_id_t) ![]const u8 {
        const constant = c.pm_constant_pool_id_to_constant(&self.internal.constant_pool, const_id);
        if (constant == null) {
            return error.ConstantNotFound;
        }
        return constant.*.start[0..constant.*.length];
    }

    /// Pretty-print AST for debugging
    pub fn prettyPrint(self: *Parser, allocator: std.mem.Allocator) ![]const u8 {
        var buffer: c.pm_buffer_t = undefined;
        _ = c.pm_buffer_init(&buffer);
        defer c.pm_buffer_free(&buffer);

        const ast = self.ast orelse return "";
        c.pm_prettyprint(&buffer, &self.internal, ast);

        const output = buffer.value[0..buffer.length];
        return allocator.dupe(u8, output);
    }
};
