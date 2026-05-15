const std = @import("std");
const enc = @import("encoding.zig");

const c = @cImport(@cInclude("prism.h"));

pub const RawNode = c.pm_node_t;
pub const RANGE_FLAGS_EXCLUDE_END = c.PM_RANGE_FLAGS_EXCLUDE_END;
pub const CALL_NODE_FLAGS_SAFE_NAVIGATION = c.PM_CALL_NODE_FLAGS_SAFE_NAVIGATION;
pub const LOOP_FLAGS_BEGIN_MODIFIER = c.PM_LOOP_FLAGS_BEGIN_MODIFIER;

pub const ArgumentsNode = c.pm_arguments_node_t;
pub const ArrayNode = c.pm_array_node_t;
pub const AndNode = c.pm_and_node_t;
pub const BeginNode = c.pm_begin_node_t;
pub const BlockNode = c.pm_block_node_t;
pub const BlockParametersNode = c.pm_block_parameters_node_t;
pub const BlockParameterNode = c.pm_block_parameter_node_t;
pub const CallNode = c.pm_call_node_t;
pub const CallAndWriteNode = c.pm_call_and_write_node_t;
pub const CallOperatorWriteNode = c.pm_call_operator_write_node_t;
pub const CallOrWriteNode = c.pm_call_or_write_node_t;
pub const CaseNode = c.pm_case_node_t;
pub const ClassNode = c.pm_class_node_t;
pub const SingletonClassNode = c.pm_singleton_class_node_t;
pub const ConstantPathNode = c.pm_constant_path_node_t;
pub const ConstantReadNode = c.pm_constant_read_node_t;
pub const ConstantAndWriteNode = c.pm_constant_and_write_node_t;
pub const ConstantOrWriteNode = c.pm_constant_or_write_node_t;
pub const ConstantPathWriteNode = c.pm_constant_path_write_node_t;
pub const ConstantWriteNode = c.pm_constant_write_node_t;
pub const DefNode = c.pm_def_node_t;
pub const DefinedNode = c.pm_defined_node_t;
pub const ElseNode = c.pm_else_node_t;
pub const EnsureNode = c.pm_ensure_node_t;
pub const FalseNode = c.pm_false_node_t;
pub const IfNode = c.pm_if_node_t;
pub const IntegerNode = c.pm_integer_node_t;
pub const FloatNode = c.pm_float_node_t;
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
pub const ForwardingParameterNode = c.pm_forwarding_parameter_node_t;
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
pub const RedoNode = c.pm_redo_node_t;
pub const ReturnNode = c.pm_return_node_t;
pub const NextNode = c.pm_next_node_t;
pub const SelfNode = c.pm_self_node_t;
pub const SourceFileNode = c.pm_source_file_node_t;
pub const SourceLineNode = c.pm_source_line_node_t;
pub const SourceEncodingNode = c.pm_source_encoding_node_t;
pub const StatementsNode = c.pm_statements_node_t;
pub const StringNode = c.pm_string_node_t;
pub const SymbolNode = c.pm_symbol_node_t;
pub const TrueNode = c.pm_true_node_t;
pub const UndefNode = c.pm_undef_node_t;
pub const WhenNode = c.pm_when_node_t;
pub const YieldNode = c.pm_yield_node_t;
pub const WhileNode = c.pm_while_node_t;
pub const UnlessNode = c.pm_unless_node_t;
pub const UntilNode = c.pm_until_node_t;
pub const BreakNode = c.pm_break_node_t;
pub const HashNode = c.pm_hash_node_t;
pub const AssocNode = c.pm_assoc_node_t;
pub const AssocSplatNode = c.pm_assoc_splat_node_t;
pub const LambdaNode = c.pm_lambda_node_t;
pub const MissingNode = c.pm_missing_node_t;
pub const GlobalVariableReadNode = c.pm_global_variable_read_node_t;
pub const BackReferenceReadNode = c.pm_back_reference_read_node_t;
pub const NumberedReferenceReadNode = c.pm_numbered_reference_read_node_t;
pub const GlobalVariableAndWriteNode = c.pm_global_variable_and_write_node_t;
pub const GlobalVariableOperatorWriteNode = c.pm_global_variable_operator_write_node_t;
pub const GlobalVariableOrWriteNode = c.pm_global_variable_or_write_node_t;
pub const GlobalVariableWriteNode = c.pm_global_variable_write_node_t;
pub const InstanceVariableReadNode = c.pm_instance_variable_read_node_t;
pub const InstanceVariableAndWriteNode = c.pm_instance_variable_and_write_node_t;
pub const InstanceVariableOrWriteNode = c.pm_instance_variable_or_write_node_t;
pub const InstanceVariableOperatorWriteNode = c.pm_instance_variable_operator_write_node_t;
pub const InstanceVariableWriteNode = c.pm_instance_variable_write_node_t;
pub const LocalVariableAndWriteNode = c.pm_local_variable_and_write_node_t;
pub const LocalVariableOrWriteNode = c.pm_local_variable_or_write_node_t;
pub const LocalVariableOperatorWriteNode = c.pm_local_variable_operator_write_node_t;
pub const BlockArgumentNode = c.pm_block_argument_node_t;
pub const EmbeddedStatementsNode = c.pm_embedded_statements_node_t;
pub const EmbeddedVariableNode = c.pm_embedded_variable_node_t;
pub const InterpolatedRegularExpressionNode = c.pm_interpolated_regular_expression_node_t;
pub const InterpolatedStringNode = c.pm_interpolated_string_node_t;
pub const InterpolatedSymbolNode = c.pm_interpolated_symbol_node_t;
pub const XStringNode = c.pm_x_string_node_t;
pub const InterpolatedXStringNode = c.pm_interpolated_x_string_node_t;
pub const ForwardingSuperNode = c.pm_forwarding_super_node_t;
pub const SuperNode = c.pm_super_node_t;
pub const RegularExpressionNode = c.pm_regular_expression_node_t;
pub const AliasMethodNode = c.pm_alias_method_node_t;
pub const MultiWriteNode = c.pm_multi_write_node_t;
pub const MultiTargetNode = c.pm_multi_target_node_t;
pub const SplatNode = c.pm_splat_node_t;
pub const ImplicitNode = c.pm_implicit_node_t;
pub const ImplicitRestNode = c.pm_implicit_rest_node_t;
pub const GlobalVariableTargetNode = c.pm_global_variable_target_node_t;
pub const InstanceVariableTargetNode = c.pm_instance_variable_target_node_t;
pub const ConstantTargetNode = c.pm_constant_target_node_t;
pub const ConstantPathTargetNode = c.pm_constant_path_target_node_t;
pub const ClassVariableTargetNode = c.pm_class_variable_target_node_t;
pub const ClassVariableReadNode = c.pm_class_variable_read_node_t;
pub const ClassVariableWriteNode = c.pm_class_variable_write_node_t;
pub const ClassVariableAndWriteNode = c.pm_class_variable_and_write_node_t;
pub const ClassVariableOrWriteNode = c.pm_class_variable_or_write_node_t;
pub const ClassVariableOperatorWriteNode = c.pm_class_variable_operator_write_node_t;
pub const IndexTargetNode = c.pm_index_target_node_t;
pub const IndexAndWriteNode = c.pm_index_and_write_node_t;
pub const IndexOrWriteNode = c.pm_index_or_write_node_t;
pub const IndexOperatorWriteNode = c.pm_index_operator_write_node_t;
pub const CallTargetNode = c.pm_call_target_node_t;

pub const REGEXP_FLAGS_IGNORE_CASE = c.PM_REGULAR_EXPRESSION_FLAGS_IGNORE_CASE;
pub const REGEXP_FLAGS_EXTENDED = c.PM_REGULAR_EXPRESSION_FLAGS_EXTENDED;
pub const REGEXP_FLAGS_MULTI_LINE = c.PM_REGULAR_EXPRESSION_FLAGS_MULTI_LINE;
pub const REGEXP_FLAGS_EUC_JP = c.PM_REGULAR_EXPRESSION_FLAGS_EUC_JP;
pub const REGEXP_FLAGS_ASCII_8BIT = c.PM_REGULAR_EXPRESSION_FLAGS_ASCII_8BIT;
pub const REGEXP_FLAGS_WINDOWS_31J = c.PM_REGULAR_EXPRESSION_FLAGS_WINDOWS_31J;
pub const REGEXP_FLAGS_UTF_8 = c.PM_REGULAR_EXPRESSION_FLAGS_UTF_8;
pub const REGEXP_FLAGS_FORCED_UTF8_ENCODING = c.PM_REGULAR_EXPRESSION_FLAGS_FORCED_UTF8_ENCODING;
pub const REGEXP_FLAGS_FORCED_BINARY_ENCODING = c.PM_REGULAR_EXPRESSION_FLAGS_FORCED_BINARY_ENCODING;
pub const REGEXP_FLAGS_FORCED_US_ASCII_ENCODING = c.PM_REGULAR_EXPRESSION_FLAGS_FORCED_US_ASCII_ENCODING;
pub const STRING_FLAGS_FORCED_UTF8_ENCODING = c.PM_STRING_FLAGS_FORCED_UTF8_ENCODING;
pub const STRING_FLAGS_FORCED_BINARY_ENCODING = c.PM_STRING_FLAGS_FORCED_BINARY_ENCODING;
pub const STRING_FLAGS_FROZEN = c.PM_STRING_FLAGS_FROZEN;
pub const STRING_FLAGS_MUTABLE = c.PM_STRING_FLAGS_MUTABLE;

pub const Node = union(enum) {
    array: *ArrayNode,
    and_node: *AndNode,
    begin: *BeginNode,
    block: *BlockNode,
    block_parameters: *BlockParametersNode,
    block_parameter: *BlockParameterNode,
    call: *CallNode,
    call_and_write: *CallAndWriteNode,
    call_operator_write: *CallOperatorWriteNode,
    call_or_write: *CallOrWriteNode,
    case_node: *CaseNode,
    class: *ClassNode,
    singleton_class: *SingletonClassNode,
    constant_path: *ConstantPathNode,
    constant_read: *ConstantReadNode,
    constant_and_write: *ConstantAndWriteNode,
    constant_or_write: *ConstantOrWriteNode,
    constant_path_write: *ConstantPathWriteNode,
    constant_write: *ConstantWriteNode,
    def: *DefNode,
    defined: *DefinedNode,
    else_node: *ElseNode,
    ensure: *EnsureNode,
    false_node: *FalseNode,
    if_node: *IfNode,
    integer: *IntegerNode,
    float: *FloatNode,
    local_variable_read: *LocalVariableReadNode,
    local_variable_target: *LocalVariableTargetNode,
    local_variable_and_write: *LocalVariableAndWriteNode,
    local_variable_or_write: *LocalVariableOrWriteNode,
    local_variable_operator_write: *LocalVariableOperatorWriteNode,
    local_variable_write: *LocalVariableWriteNode,
    module: *ModuleNode,
    nil_node: *NilNode,
    parentheses: *ParenthesesNode,
    program: *ProgramNode,
    range: *RangeNode,
    required_parameter: *RequiredParameterNode,
    optional_parameter: *OptionalParameterNode,
    forwarding_parameter: *ForwardingParameterNode,
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
    redo: *RedoNode,
    return_node: *ReturnNode,
    next_node: *NextNode,
    self: *SelfNode,
    source_encoding: *SourceEncodingNode,
    source_file: *SourceFileNode,
    source_line: *SourceLineNode,
    statements: *StatementsNode,
    string: *StringNode,
    symbol: *SymbolNode,
    true_node: *TrueNode,
    undef_node: *UndefNode,
    when_node: *WhenNode,
    yield: *YieldNode,
    while_node: *WhileNode,
    unless_node: *UnlessNode,
    until_node: *UntilNode,
    break_node: *BreakNode,
    hash: *HashNode,
    assoc: *AssocNode,
    assoc_splat: *AssocSplatNode,
    lambda: *LambdaNode,
    missing: *MissingNode,
    global_variable_read: *GlobalVariableReadNode,
    back_reference_read: *BackReferenceReadNode,
    numbered_reference_read: *NumberedReferenceReadNode,
    global_variable_and_write: *GlobalVariableAndWriteNode,
    global_variable_operator_write: *GlobalVariableOperatorWriteNode,
    global_variable_or_write: *GlobalVariableOrWriteNode,
    global_variable_write: *GlobalVariableWriteNode,
    instance_variable_read: *InstanceVariableReadNode,
    instance_variable_and_write: *InstanceVariableAndWriteNode,
    instance_variable_or_write: *InstanceVariableOrWriteNode,
    instance_variable_operator_write: *InstanceVariableOperatorWriteNode,
    instance_variable_write: *InstanceVariableWriteNode,
    block_argument: *BlockArgumentNode,
    embedded_statements: *EmbeddedStatementsNode,
    embedded_variable: *EmbeddedVariableNode,
    interpolated_regular_expression: *InterpolatedRegularExpressionNode,
    interpolated_string: *InterpolatedStringNode,
    interpolated_symbol: *InterpolatedSymbolNode,
    x_string: *XStringNode,
    interpolated_x_string: *InterpolatedXStringNode,
    forwarding_super: *ForwardingSuperNode,
    super_node: *SuperNode,
    regular_expression: *RegularExpressionNode,
    alias_method: *AliasMethodNode,
    multi_write: *MultiWriteNode,
    multi_target: *MultiTargetNode,
    splat: *SplatNode,
    implicit: *ImplicitNode,
    implicit_rest: *ImplicitRestNode,
    global_variable_target: *GlobalVariableTargetNode,
    instance_variable_target: *InstanceVariableTargetNode,
    constant_target: *ConstantTargetNode,
    constant_path_target: *ConstantPathTargetNode,
    class_variable_target: *ClassVariableTargetNode,
    class_variable_read: *ClassVariableReadNode,
    class_variable_write: *ClassVariableWriteNode,
    class_variable_and_write: *ClassVariableAndWriteNode,
    class_variable_or_write: *ClassVariableOrWriteNode,
    class_variable_operator_write: *ClassVariableOperatorWriteNode,
    index_target: *IndexTargetNode,
    index_and_write: *IndexAndWriteNode,
    index_or_write: *IndexOrWriteNode,
    index_operator_write: *IndexOperatorWriteNode,
    call_target: *CallTargetNode,
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
        return initWithEncoding(allocator, source, source_file, null);
    }

    /// Initialize parser with source code and optional explicit source encoding.
    pub fn initWithEncoding(
        allocator: std.mem.Allocator,
        source: []const u8,
        source_file: ?[]const u8,
        source_encoding: ?enc.Encoding,
    ) !Parser {
        var parser: c.pm_parser_t = undefined;
        var options: c.pm_options_t = std.mem.zeroes(c.pm_options_t);
        defer c.pm_options_free(&options);

        if (source_encoding) |encoding| {
            c.pm_options_encoding_set(&options, encoding.name().ptr);
            c.pm_options_encoding_locked_set(&options, true);
        }

        c.pm_parser_init(&parser, source.ptr, source.len, &options);

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

    pub fn prettyPrintNodeAlloc(self: *Parser, node: *RawNode) ![]u8 {
        var buffer: c.pm_buffer_t = undefined;
        if (!c.pm_buffer_init(&buffer)) {
            return error.OutOfMemory;
        }
        defer c.pm_buffer_free(&buffer);

        c.pm_prettyprint(&buffer, &self.internal, node);
        const output = @as([*]u8, @ptrCast(buffer.value))[0..buffer.length];
        return self.allocator.dupe(u8, output);
    }

    pub fn integerNodeToDecimalString(self: *Parser, node: *IntegerNode) ![]u8 {
        var buffer: c.pm_buffer_t = undefined;
        if (!c.pm_buffer_init(&buffer)) {
            return error.OutOfMemory;
        }
        defer c.pm_buffer_free(&buffer);

        c.pm_integer_string(&buffer, &node.value);
        const out = @as([*]u8, @ptrCast(buffer.value))[0..buffer.length];
        return self.allocator.dupe(u8, out);
    }

    pub fn integerNodeToI64(_: *Parser, node: *IntegerNode) ?i64 {
        const pm_int = node.value;
        const mag: u64 = if (pm_int.length == 0) blk: {
            break :blk pm_int.value;
        } else blk: {
            if (pm_int.length > 2) return null;
            const words = pm_int.values orelse return null;
            var m: u64 = words[0];
            if (pm_int.length == 2) {
                m |= (@as(u64, words[1]) << 32);
            }
            break :blk m;
        };

        if (pm_int.negative) {
            const min_abs: u64 = (@as(u64, 1) << 63);
            if (mag > min_abs) return null;
            if (mag == min_abs) return std.math.minInt(i64);
            return -@as(i64, @intCast(mag));
        }

        if (mag > std.math.maxInt(i64)) return null;
        return @intCast(mag);
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

        if (node_type == c.PM_FLOAT_NODE) {
            return Node{ .float = @ptrCast(raw) };
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
        if (node_type == c.PM_CONSTANT_AND_WRITE_NODE) {
            return Node{ .constant_and_write = @ptrCast(raw) };
        }
        if (node_type == c.PM_CONSTANT_OR_WRITE_NODE) {
            return Node{ .constant_or_write = @ptrCast(raw) };
        }
        if (node_type == c.PM_CONSTANT_PATH_WRITE_NODE) {
            return Node{ .constant_path_write = @ptrCast(raw) };
        }

        if (node_type == c.PM_CONSTANT_PATH_NODE) {
            return Node{ .constant_path = @ptrCast(raw) };
        }

        if (node_type == c.PM_CALL_NODE) {
            return Node{ .call = @ptrCast(raw) };
        }

        if (node_type == c.PM_CALL_AND_WRITE_NODE) {
            return Node{ .call_and_write = @ptrCast(raw) };
        }

        if (node_type == c.PM_CALL_OPERATOR_WRITE_NODE) {
            return Node{ .call_operator_write = @ptrCast(raw) };
        }

        if (node_type == c.PM_CALL_OR_WRITE_NODE) {
            return Node{ .call_or_write = @ptrCast(raw) };
        }

        if (node_type == c.PM_CASE_NODE) {
            return Node{ .case_node = @ptrCast(raw) };
        }

        if (node_type == c.PM_MODULE_NODE) {
            return Node{ .module = @ptrCast(raw) };
        }

        if (node_type == c.PM_DEF_NODE) {
            return Node{ .def = @ptrCast(raw) };
        }

        if (node_type == c.PM_DEFINED_NODE) {
            return Node{ .defined = @ptrCast(raw) };
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
        if (node_type == c.PM_LOCAL_VARIABLE_AND_WRITE_NODE) {
            return Node{ .local_variable_and_write = @ptrCast(raw) };
        }
        if (node_type == c.PM_LOCAL_VARIABLE_OR_WRITE_NODE) {
            return Node{ .local_variable_or_write = @ptrCast(raw) };
        }

        if (node_type == c.PM_LOCAL_VARIABLE_OPERATOR_WRITE_NODE) {
            return Node{ .local_variable_operator_write = @ptrCast(raw) };
        }

        if (node_type == c.PM_REQUIRED_PARAMETER_NODE) {
            return Node{ .required_parameter = @ptrCast(raw) };
        }

        if (node_type == c.PM_FORWARDING_PARAMETER_NODE) {
            return Node{ .forwarding_parameter = @ptrCast(raw) };
        }

        if (node_type == c.PM_CLASS_NODE) {
            return Node{ .class = @ptrCast(raw) };
        }

        if (node_type == c.PM_SINGLETON_CLASS_NODE) {
            return Node{ .singleton_class = @ptrCast(raw) };
        }

        if (node_type == c.PM_SELF_NODE) {
            return Node{ .self = @ptrCast(raw) };
        }

        if (node_type == c.PM_SOURCE_FILE_NODE) {
            return Node{ .source_file = @ptrCast(raw) };
        }

        if (node_type == c.PM_SOURCE_LINE_NODE) {
            return Node{ .source_line = @ptrCast(raw) };
        }

        if (node_type == c.PM_SOURCE_ENCODING_NODE) {
            return Node{ .source_encoding = @ptrCast(raw) };
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

        if (node_type == c.PM_WHEN_NODE) {
            return Node{ .when_node = @ptrCast(raw) };
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

        if (node_type == c.PM_REDO_NODE) {
            return Node{ .redo = @ptrCast(raw) };
        }

        if (node_type == c.PM_RETURN_NODE) {
            return Node{ .return_node = @ptrCast(raw) };
        }

        if (node_type == c.PM_NEXT_NODE) {
            return Node{ .next_node = @ptrCast(raw) };
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
        if (node_type == c.PM_ASSOC_SPLAT_NODE) {
            return Node{ .assoc_splat = @ptrCast(raw) };
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
        if (node_type == c.PM_BACK_REFERENCE_READ_NODE) {
            return Node{ .back_reference_read = @ptrCast(raw) };
        }
        if (node_type == c.PM_NUMBERED_REFERENCE_READ_NODE) {
            return Node{ .numbered_reference_read = @ptrCast(raw) };
        }

        if (node_type == c.PM_GLOBAL_VARIABLE_WRITE_NODE) {
            return Node{ .global_variable_write = @ptrCast(raw) };
        }
        if (node_type == c.PM_GLOBAL_VARIABLE_AND_WRITE_NODE) {
            return Node{ .global_variable_and_write = @ptrCast(raw) };
        }
        if (node_type == c.PM_GLOBAL_VARIABLE_OPERATOR_WRITE_NODE) {
            return Node{ .global_variable_operator_write = @ptrCast(raw) };
        }
        if (node_type == c.PM_GLOBAL_VARIABLE_OR_WRITE_NODE) {
            return Node{ .global_variable_or_write = @ptrCast(raw) };
        }

        if (node_type == c.PM_INSTANCE_VARIABLE_READ_NODE) {
            return Node{ .instance_variable_read = @ptrCast(raw) };
        }

        if (node_type == c.PM_INSTANCE_VARIABLE_WRITE_NODE) {
            return Node{ .instance_variable_write = @ptrCast(raw) };
        }
        if (node_type == c.PM_INSTANCE_VARIABLE_AND_WRITE_NODE) {
            return Node{ .instance_variable_and_write = @ptrCast(raw) };
        }
        if (node_type == c.PM_INSTANCE_VARIABLE_OR_WRITE_NODE) {
            return Node{ .instance_variable_or_write = @ptrCast(raw) };
        }
        if (node_type == c.PM_INSTANCE_VARIABLE_OPERATOR_WRITE_NODE) {
            return Node{ .instance_variable_operator_write = @ptrCast(raw) };
        }

        if (node_type == c.PM_BLOCK_ARGUMENT_NODE) {
            return Node{ .block_argument = @ptrCast(raw) };
        }

        if (node_type == c.PM_EMBEDDED_STATEMENTS_NODE) {
            return Node{ .embedded_statements = @ptrCast(raw) };
        }

        if (node_type == c.PM_EMBEDDED_VARIABLE_NODE) {
            return Node{ .embedded_variable = @ptrCast(raw) };
        }

        if (node_type == c.PM_INTERPOLATED_REGULAR_EXPRESSION_NODE) {
            return Node{ .interpolated_regular_expression = @ptrCast(raw) };
        }

        if (node_type == c.PM_INTERPOLATED_STRING_NODE) {
            return Node{ .interpolated_string = @ptrCast(raw) };
        }

        if (node_type == c.PM_INTERPOLATED_SYMBOL_NODE) {
            return Node{ .interpolated_symbol = @ptrCast(raw) };
        }

        if (node_type == c.PM_X_STRING_NODE) {
            return Node{ .x_string = @ptrCast(raw) };
        }

        if (node_type == c.PM_INTERPOLATED_X_STRING_NODE) {
            return Node{ .interpolated_x_string = @ptrCast(raw) };
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

        if (node_type == c.PM_UNDEF_NODE) {
            return Node{ .undef_node = @ptrCast(raw) };
        }

        if (node_type == c.PM_MULTI_WRITE_NODE) {
            return Node{ .multi_write = @ptrCast(raw) };
        }

        if (node_type == c.PM_MULTI_TARGET_NODE) {
            return Node{ .multi_target = @ptrCast(raw) };
        }

        if (node_type == c.PM_SPLAT_NODE) {
            return Node{ .splat = @ptrCast(raw) };
        }

        if (node_type == c.PM_IMPLICIT_NODE) {
            return Node{ .implicit = @ptrCast(raw) };
        }

        if (node_type == c.PM_IMPLICIT_REST_NODE) {
            return Node{ .implicit_rest = @ptrCast(raw) };
        }

        if (node_type == c.PM_GLOBAL_VARIABLE_TARGET_NODE) {
            return Node{ .global_variable_target = @ptrCast(raw) };
        }

        if (node_type == c.PM_INSTANCE_VARIABLE_TARGET_NODE) {
            return Node{ .instance_variable_target = @ptrCast(raw) };
        }

        if (node_type == c.PM_CONSTANT_TARGET_NODE) {
            return Node{ .constant_target = @ptrCast(raw) };
        }

        if (node_type == c.PM_CONSTANT_PATH_TARGET_NODE) {
            return Node{ .constant_path_target = @ptrCast(raw) };
        }

        if (node_type == c.PM_CLASS_VARIABLE_TARGET_NODE) {
            return Node{ .class_variable_target = @ptrCast(raw) };
        }

        if (node_type == c.PM_CLASS_VARIABLE_READ_NODE) {
            return Node{ .class_variable_read = @ptrCast(raw) };
        }

        if (node_type == c.PM_CLASS_VARIABLE_WRITE_NODE) {
            return Node{ .class_variable_write = @ptrCast(raw) };
        }

        if (node_type == c.PM_CLASS_VARIABLE_AND_WRITE_NODE) {
            return Node{ .class_variable_and_write = @ptrCast(raw) };
        }

        if (node_type == c.PM_CLASS_VARIABLE_OR_WRITE_NODE) {
            return Node{ .class_variable_or_write = @ptrCast(raw) };
        }

        if (node_type == c.PM_CLASS_VARIABLE_OPERATOR_WRITE_NODE) {
            return Node{ .class_variable_operator_write = @ptrCast(raw) };
        }

        if (node_type == c.PM_INDEX_TARGET_NODE) {
            return Node{ .index_target = @ptrCast(raw) };
        }

        if (node_type == c.PM_INDEX_AND_WRITE_NODE) {
            return Node{ .index_and_write = @ptrCast(raw) };
        }

        if (node_type == c.PM_INDEX_OR_WRITE_NODE) {
            return Node{ .index_or_write = @ptrCast(raw) };
        }

        if (node_type == c.PM_INDEX_OPERATOR_WRITE_NODE) {
            return Node{ .index_operator_write = @ptrCast(raw) };
        }

        if (node_type == c.PM_CALL_TARGET_NODE) {
            return Node{ .call_target = @ptrCast(raw) };
        }

        var stdout_buffer: [8192]u8 = undefined;
        var threaded: std.Io.Threaded = .init(std.heap.page_allocator, .{});
        defer threaded.deinit();
        var stdout_writer = std.Io.File.stdout().writer(threaded.io(), &stdout_buffer);
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
