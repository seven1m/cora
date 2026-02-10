const std = @import("std");

const c = @cImport(@cInclude("prism.h"));

pub const RawNode = c.pm_node_t;
pub const RANGE_FLAGS_EXCLUDE_END = c.PM_RANGE_FLAGS_EXCLUDE_END;

pub const ArgumentsNode = c.pm_arguments_node_t;
pub const ArrayNode = c.pm_array_node_t;
pub const AndNode = c.pm_and_node_t;
pub const BeginNode = c.pm_begin_node_t;
pub const BlockNode = c.pm_block_node_t;
pub const BlockParametersNode = c.pm_block_parameters_node_t;
pub const BlockParameterNode = c.pm_block_parameter_node_t;
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
pub const ParenthesesNode = c.pm_parentheses_node_t;
pub const ProgramNode = c.pm_program_node_t;
pub const RangeNode = c.pm_range_node_t;
pub const RequiredParameterNode = c.pm_required_parameter_node_t;
pub const OptionalParameterNode = c.pm_optional_parameter_node_t;
pub const OrNode = c.pm_or_node_t;
pub const RestParameterNode = c.pm_rest_parameter_node_t;
pub const RequiredKeywordParameterNode = c.pm_required_keyword_parameter_node_t;
pub const OptionalKeywordParameterNode = c.pm_optional_keyword_parameter_node_t;
pub const KeywordRestParameterNode = c.pm_keyword_rest_parameter_node_t;
pub const NoKeywordsParameterNode = c.pm_no_keywords_parameter_node_t;
pub const KeywordHashNode = c.pm_keyword_hash_node_t;
pub const RescueNode = c.pm_rescue_node_t;
pub const RescueModifierNode = c.pm_rescue_modifier_node_t;
pub const RetryNode = c.pm_retry_node_t;
pub const ReturnNode = c.pm_return_node_t;
pub const SelfNode = c.pm_self_node_t;
pub const StatementsNode = c.pm_statements_node_t;
pub const StringNode = c.pm_string_node_t;
pub const SymbolNode = c.pm_symbol_node_t;
pub const TrueNode = c.pm_true_node_t;
pub const YieldNode = c.pm_yield_node_t;
pub const WhileNode = c.pm_while_node_t;
pub const UnlessNode = c.pm_unless_node_t;
pub const UntilNode = c.pm_until_node_t;
pub const BreakNode = c.pm_break_node_t;
pub const HashNode = c.pm_hash_node_t;
pub const AssocNode = c.pm_assoc_node_t;
pub const LambdaNode = c.pm_lambda_node_t;
pub const MissingNode = c.pm_missing_node_t;
pub const GlobalVariableReadNode = c.pm_global_variable_read_node_t;
pub const GlobalVariableWriteNode = c.pm_global_variable_write_node_t;
pub const InstanceVariableReadNode = c.pm_instance_variable_read_node_t;
pub const InstanceVariableWriteNode = c.pm_instance_variable_write_node_t;
pub const BlockArgumentNode = c.pm_block_argument_node_t;
pub const EmbeddedStatementsNode = c.pm_embedded_statements_node_t;
pub const InterpolatedStringNode = c.pm_interpolated_string_node_t;
pub const ForwardingSuperNode = c.pm_forwarding_super_node_t;
pub const SuperNode = c.pm_super_node_t;
pub const RegularExpressionNode = c.pm_regular_expression_node_t;
pub const AliasMethodNode = c.pm_alias_method_node_t;

pub const REGEXP_FLAGS_IGNORE_CASE = c.PM_REGULAR_EXPRESSION_FLAGS_IGNORE_CASE;
pub const REGEXP_FLAGS_EXTENDED = c.PM_REGULAR_EXPRESSION_FLAGS_EXTENDED;
pub const REGEXP_FLAGS_MULTI_LINE = c.PM_REGULAR_EXPRESSION_FLAGS_MULTI_LINE;

pub const Node = union(enum) {
    array: *ArrayNode,
    and_node: *AndNode,
    begin: *BeginNode,
    block: *BlockNode,
    block_parameters: *BlockParametersNode,
    block_parameter: *BlockParameterNode,
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
    parentheses: *ParenthesesNode,
    program: *ProgramNode,
    range: *RangeNode,
    required_parameter: *RequiredParameterNode,
    optional_parameter: *OptionalParameterNode,
    or_node: *OrNode,
    rest_parameter: *RestParameterNode,
    required_keyword_parameter: *RequiredKeywordParameterNode,
    optional_keyword_parameter: *OptionalKeywordParameterNode,
    keyword_rest_parameter: *KeywordRestParameterNode,
    no_keywords_parameter: *NoKeywordsParameterNode,
    keyword_hash: *KeywordHashNode,
    rescue: *RescueNode,
    rescue_modifier: *RescueModifierNode,
    retry: *RetryNode,
    return_node: *ReturnNode,
    self: *SelfNode,
    statements: *StatementsNode,
    string: *StringNode,
    symbol: *SymbolNode,
    true_node: *TrueNode,
    yield: *YieldNode,
    while_node: *WhileNode,
    unless_node: *UnlessNode,
    until_node: *UntilNode,
    break_node: *BreakNode,
    hash: *HashNode,
    assoc: *AssocNode,
    lambda: *LambdaNode,
    missing: *MissingNode,
    global_variable_read: *GlobalVariableReadNode,
    global_variable_write: *GlobalVariableWriteNode,
    instance_variable_read: *InstanceVariableReadNode,
    instance_variable_write: *InstanceVariableWriteNode,
    block_argument: *BlockArgumentNode,
    embedded_statements: *EmbeddedStatementsNode,
    interpolated_string: *InterpolatedStringNode,
    forwarding_super: *ForwardingSuperNode,
    super_node: *SuperNode,
    regular_expression: *RegularExpressionNode,
    alias_method: *AliasMethodNode,
};

/// Parser wraps Prism's parser and AST lifecycle
pub const Parser = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    internal: c.pm_parser_t,
    ast: *ProgramNode,
    source_file: ?[]const u8 = null,

    /// Initialize parser with source code
    pub fn init(allocator: std.mem.Allocator, source: []const u8, source_file: ?[]const u8) !Parser {
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
            .source_file = source_file,
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

        if (node_type == c.PM_RANGE_NODE) {
            return Node{ .range = @ptrCast(raw) };
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

        if (node_type == c.PM_UNLESS_NODE) {
            return Node{ .unless_node = @ptrCast(raw) };
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

        if (node_type == c.PM_PARENTHESES_NODE) {
            return Node{ .parentheses = @ptrCast(raw) };
        }

        if (node_type == c.PM_YIELD_NODE) {
            return Node{ .yield = @ptrCast(raw) };
        }

        if (node_type == c.PM_ARRAY_NODE) {
            return Node{ .array = @ptrCast(raw) };
        }

        if (node_type == c.PM_AND_NODE) {
            return Node{ .and_node = @ptrCast(raw) };
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

        if (node_type == c.PM_BLOCK_PARAMETER_NODE) {
            return Node{ .block_parameter = @ptrCast(raw) };
        }

        if (node_type == c.PM_RESCUE_NODE) {
            return Node{ .rescue = @ptrCast(raw) };
        }

        if (node_type == c.PM_RESCUE_MODIFIER_NODE) {
            return Node{ .rescue_modifier = @ptrCast(raw) };
        }

        if (node_type == c.PM_RETRY_NODE) {
            return Node{ .retry = @ptrCast(raw) };
        }

        if (node_type == c.PM_RETURN_NODE) {
            return Node{ .return_node = @ptrCast(raw) };
        }

        if (node_type == c.PM_WHILE_NODE) {
            return Node{ .while_node = @ptrCast(raw) };
        }

        if (node_type == c.PM_UNTIL_NODE) {
            return Node{ .until_node = @ptrCast(raw) };
        }

        if (node_type == c.PM_BREAK_NODE) {
            return Node{ .break_node = @ptrCast(raw) };
        }

        if (node_type == c.PM_HASH_NODE) {
            return Node{ .hash = @ptrCast(raw) };
        }

        if (node_type == c.PM_ASSOC_NODE) {
            return Node{ .assoc = @ptrCast(raw) };
        }

        if (node_type == c.PM_LAMBDA_NODE) {
            return Node{ .lambda = @ptrCast(raw) };
        }

        if (node_type == c.PM_MISSING_NODE) {
            return Node{ .missing = @ptrCast(raw) };
        }

        if (node_type == c.PM_GLOBAL_VARIABLE_READ_NODE) {
            return Node{ .global_variable_read = @ptrCast(raw) };
        }

        if (node_type == c.PM_GLOBAL_VARIABLE_WRITE_NODE) {
            return Node{ .global_variable_write = @ptrCast(raw) };
        }

        if (node_type == c.PM_INSTANCE_VARIABLE_READ_NODE) {
            return Node{ .instance_variable_read = @ptrCast(raw) };
        }

        if (node_type == c.PM_INSTANCE_VARIABLE_WRITE_NODE) {
            return Node{ .instance_variable_write = @ptrCast(raw) };
        }

        if (node_type == c.PM_BLOCK_ARGUMENT_NODE) {
            return Node{ .block_argument = @ptrCast(raw) };
        }

        if (node_type == c.PM_EMBEDDED_STATEMENTS_NODE) {
            return Node{ .embedded_statements = @ptrCast(raw) };
        }

        if (node_type == c.PM_INTERPOLATED_STRING_NODE) {
            return Node{ .interpolated_string = @ptrCast(raw) };
        }

        if (node_type == c.PM_OPTIONAL_PARAMETER_NODE) {
            return Node{ .optional_parameter = @ptrCast(raw) };
        }

        if (node_type == c.PM_OR_NODE) {
            return Node{ .or_node = @ptrCast(raw) };
        }

        if (node_type == c.PM_REST_PARAMETER_NODE) {
            return Node{ .rest_parameter = @ptrCast(raw) };
        }

        if (node_type == c.PM_REQUIRED_KEYWORD_PARAMETER_NODE) {
            return Node{ .required_keyword_parameter = @ptrCast(raw) };
        }

        if (node_type == c.PM_OPTIONAL_KEYWORD_PARAMETER_NODE) {
            return Node{ .optional_keyword_parameter = @ptrCast(raw) };
        }

        if (node_type == c.PM_KEYWORD_REST_PARAMETER_NODE) {
            return Node{ .keyword_rest_parameter = @ptrCast(raw) };
        }

        if (node_type == c.PM_NO_KEYWORDS_PARAMETER_NODE) {
            return Node{ .no_keywords_parameter = @ptrCast(raw) };
        }

        if (node_type == c.PM_KEYWORD_HASH_NODE) {
            return Node{ .keyword_hash = @ptrCast(raw) };
        }

        if (node_type == c.PM_FORWARDING_SUPER_NODE) {
            return Node{ .forwarding_super = @ptrCast(raw) };
        }

        if (node_type == c.PM_SUPER_NODE) {
            return Node{ .super_node = @ptrCast(raw) };
        }

        if (node_type == c.PM_REGULAR_EXPRESSION_NODE) {
            return Node{ .regular_expression = @ptrCast(raw) };
        }

        if (node_type == c.PM_ALIAS_METHOD_NODE) {
            return Node{ .alias_method = @ptrCast(raw) };
        }

        var stdout_buffer: [8192]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;
        try self.prettyPrintNode(raw, stdout);
        try stdout.flush();
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
