const std = @import("std");

const c = @cImport(@cInclude("prism.h"));

pub const RawNode = c.pm_node_t;

pub const ArgumentsNode = c.pm_arguments_node_t;
pub const CallNode = c.pm_call_node_t;
pub const ConstantReadNode = c.pm_constant_read_node_t;
pub const ConstantWriteNode = c.pm_constant_write_node_t;
pub const DefNode = c.pm_def_node_t;
pub const IntegerNode = c.pm_integer_node_t;
pub const ModuleNode = c.pm_module_node;
pub const ProgramNode = c.pm_program_node_t;
pub const StatementsNode = c.pm_statements_node_t;
pub const StringNode = c.pm_string_node_t;
pub const SymbolNode = c.pm_symbol_node_t;

pub const Node = union(enum) {
    call: *CallNode,
    constant_read: *ConstantReadNode,
    constant_write: *ConstantWriteNode,
    def: *DefNode,
    integer: *IntegerNode,
    module: *ModuleNode,
    program: *ProgramNode,
    statements: *StatementsNode,
    string: *StringNode,
    symbol: *SymbolNode,
};

/// Parser wraps Prism's parser and AST lifecycle
pub const Parser = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    internal: c.pm_parser_t,
    ast: ?*RawNode,

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

    /// Show Prism node in human-readable form
    pub fn prettyPrintNode(self: *Parser, node: *RawNode) void {
        var buffer: c.pm_buffer_t = undefined;
        _ = c.pm_buffer_init(&buffer);
        defer c.pm_buffer_free(&buffer);

        c.pm_prettyprint(&buffer, &self.internal, node);
        const output = buffer.value[0..buffer.length];
        std.debug.print("{s}", .{output});
    }

    /// Convert a raw C node pointer to a typed Node
    pub fn asNode(self: *Parser, raw: *RawNode) !Node {
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

        self.prettyPrintNode(raw);
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
