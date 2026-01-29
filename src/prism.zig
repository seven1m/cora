const std = @import("std");

const c = @cImport(@cInclude("prism.h"));

pub const RawNode = c.pm_node_t;

pub const ArgumentsNode = c.pm_arguments_node_t;
pub const ArrayNode = c.pm_array_node_t;
pub const BeginNode = c.pm_begin_node_t;
pub const BlockNode = c.pm_block_node_t;
pub const BlockParametersNode = c.pm_block_parameters_node_t;
pub const CallNode = c.pm_call_node_t;
pub const ClassNode = c.pm_class_node_t;
pub const ConstantPathNode = c.pm_constant_path_node_t;
pub const ConstantReadNode = c.pm_constant_read_node_t;
pub const ConstantWriteNode = c.pm_constant_write_node_t;
pub const DefNode = c.pm_def_node_t;
pub const ElseNode = c.pm_else_node_t;
pub const EnsureNode = c.pm_ensure_node_t;
pub const FalseNode = c.pm_false_node_t;
pub const IfNode = c.pm_if_node_t;
pub const IntegerNode = c.pm_integer_node_t;
pub const LocalVariableReadNode = c.pm_local_variable_read_node_t;
pub const LocalVariableTargetNode = c.pm_local_variable_target_node_t;
pub const LocalVariableWriteNode = c.pm_local_variable_write_node_t;
pub const ModuleNode = c.pm_module_node;
pub const NilNode = c.pm_nil_node_t;
pub const ParametersNode = c.pm_parameters_node_t;
pub const ProgramNode = c.pm_program_node_t;
pub const RequiredParameterNode = c.pm_required_parameter_node_t;
pub const RescueNode = c.pm_rescue_node_t;
pub const RescueModifierNode = c.pm_rescue_modifier_node_t;
pub const SelfNode = c.pm_self_node_t;
pub const StatementsNode = c.pm_statements_node_t;
pub const StringNode = c.pm_string_node_t;
pub const SymbolNode = c.pm_symbol_node_t;
pub const TrueNode = c.pm_true_node_t;
pub const YieldNode = c.pm_yield_node_t;

pub const Node = union(enum) {
    array: *ArrayNode,
    begin: *BeginNode,
    block: *BlockNode,
    block_parameters: *BlockParametersNode,
    call: *CallNode,
    class: *ClassNode,
    constant_path: *ConstantPathNode,
    constant_read: *ConstantReadNode,
    constant_write: *ConstantWriteNode,
    def: *DefNode,
    else_node: *ElseNode,
    ensure: *EnsureNode,
    false_node: *FalseNode,
    if_node: *IfNode,
    integer: *IntegerNode,
    local_variable_read: *LocalVariableReadNode,
    local_variable_target: *LocalVariableTargetNode,
    local_variable_write: *LocalVariableWriteNode,
    module: *ModuleNode,
    nil_node: *NilNode,
    program: *ProgramNode,
    required_parameter: *RequiredParameterNode,
    rescue: *RescueNode,
    rescue_modifier: *RescueModifierNode,
    self: *SelfNode,
    statements: *StatementsNode,
    string: *StringNode,
    symbol: *SymbolNode,
    true_node: *TrueNode,
    yield: *YieldNode,
};

/// Parser wraps Prism's parser and AST lifecycle
pub const Parser = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    internal: c.pm_parser_t,
    ast: *ProgramNode,

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
            .ast = @ptrCast(ast),
        };
    }

    /// Free parser and AST
    pub fn deinit(self: *Parser) void {
        c.pm_node_destroy(null, @ptrCast(self.ast));
        c.pm_parser_free(&self.internal);
    }

    /// Get the root AST node, type-checked
    pub fn root(self: *Parser) !Node {
        return self.asNode(@ptrCast(self.ast));
    }

    /// Show Prism node in human-readable form
    pub fn prettyPrintNode(self: *Parser, node: *RawNode, writer: *std.Io.Writer) !void {
        var buffer: c.pm_buffer_t = undefined;
        _ = c.pm_buffer_init(&buffer);
        defer c.pm_buffer_free(&buffer);

        c.pm_prettyprint(&buffer, &self.internal, node);
        const output = buffer.value[0..buffer.length];
        try writer.print("{s}", .{output});
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

        if (node_type == c.PM_CONSTANT_PATH_NODE) {
            return Node{ .constant_path = @ptrCast(raw) };
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

        if (node_type == c.PM_LOCAL_VARIABLE_READ_NODE) {
            return Node{ .local_variable_read = @ptrCast(raw) };
        }

        if (node_type == c.PM_LOCAL_VARIABLE_TARGET_NODE) {
            return Node{ .local_variable_target = @ptrCast(raw) };
        }

        if (node_type == c.PM_LOCAL_VARIABLE_WRITE_NODE) {
            return Node{ .local_variable_write = @ptrCast(raw) };
        }

        if (node_type == c.PM_REQUIRED_PARAMETER_NODE) {
            return Node{ .required_parameter = @ptrCast(raw) };
        }

        if (node_type == c.PM_CLASS_NODE) {
            return Node{ .class = @ptrCast(raw) };
        }

        if (node_type == c.PM_SELF_NODE) {
            return Node{ .self = @ptrCast(raw) };
        }

        if (node_type == c.PM_IF_NODE) {
            return Node{ .if_node = @ptrCast(raw) };
        }

        if (node_type == c.PM_ELSE_NODE) {
            return Node{ .else_node = @ptrCast(raw) };
        }

        if (node_type == c.PM_ENSURE_NODE) {
            return Node{ .ensure = @ptrCast(raw) };
        }

        if (node_type == c.PM_TRUE_NODE) {
            return Node{ .true_node = @ptrCast(raw) };
        }

        if (node_type == c.PM_FALSE_NODE) {
            return Node{ .false_node = @ptrCast(raw) };
        }

        if (node_type == c.PM_NIL_NODE) {
            return Node{ .nil_node = @ptrCast(raw) };
        }

        if (node_type == c.PM_YIELD_NODE) {
            return Node{ .yield = @ptrCast(raw) };
        }

        if (node_type == c.PM_ARRAY_NODE) {
            return Node{ .array = @ptrCast(raw) };
        }

        if (node_type == c.PM_BEGIN_NODE) {
            return Node{ .begin = @ptrCast(raw) };
        }

        if (node_type == c.PM_BLOCK_NODE) {
            return Node{ .block = @ptrCast(raw) };
        }

        if (node_type == c.PM_BLOCK_PARAMETERS_NODE) {
            return Node{ .block_parameters = @ptrCast(raw) };
        }

        if (node_type == c.PM_RESCUE_NODE) {
            return Node{ .rescue = @ptrCast(raw) };
        }

        if (node_type == c.PM_RESCUE_MODIFIER_NODE) {
            return Node{ .rescue_modifier = @ptrCast(raw) };
        }

        var stdout_buffer: [8192]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;
        try self.prettyPrintNode(raw, stdout);
        return error.UnhandledNode;
    }

    pub fn getConstantName(self: *Parser, const_id: c.pm_constant_id_t) ![]const u8 {
        const constant = c.pm_constant_pool_id_to_constant(&self.internal.constant_pool, const_id);
        if (constant == null) {
            return error.ConstantNotFound;
        }
        return constant.*.start[0..constant.*.length];
    }

    pub fn getLocalVariableName(self: *Parser, const_id: c.pm_constant_id_t) ![]const u8 {
        return self.getConstantName(const_id);
    }

    /// Pretty-print AST for debugging
    pub fn prettyPrint(self: *Parser, allocator: std.mem.Allocator) ![]const u8 {
        var buffer: c.pm_buffer_t = undefined;
        _ = c.pm_buffer_init(&buffer);
        defer c.pm_buffer_free(&buffer);

        c.pm_prettyprint(&buffer, &self.internal, @ptrCast(self.ast));

        const output = buffer.value[0..buffer.length];
        return allocator.dupe(u8, output);
    }
};
