const std = @import("std");
const prism = @import("prism.zig");
const bdwgc = @import("bdwgc");
const Chunk = @import("chunk.zig").Chunk;
const VM = @import("vm.zig").VM;

pub const RuntimeError = error{
    WrongReceiverType,
    WrongArgumentCount,
    WrongArgumentType,
    InvalidClassName,
    InvalidMethodIndex,
    InvalidMethodName,
    InvalidModuleName,
    InvalidSuperclass,
    UndefinedChunk,
    UndefinedMethod,
    NoBlockGiven,
    RuntimeError,
};

pub const Method = union(enum) {
    chunk: *Chunk,
    builtin: *const fn (*VM, Value, []Value, ?*Chunk) RuntimeError!Value,
};

pub const Object = struct {
    pub const FROZEN_FLAG = 0x1;

    flags: u32,
    class: ?*ClassObject,
};

pub const SymbolObject = struct {
    object: Object,
    name: []const u8,
};

pub const StringObject = struct {
    object: Object,
    str: []const u8,
};

pub const LexicalScope = struct {
    scope_module: *ModuleObject,
    parent: ?*LexicalScope,
};

pub const ModuleObject = struct {
    object: Object,
    name: *SymbolObject,
    methods: std.AutoHashMap(*SymbolObject, Method),
    constants: std.AutoHashMap(*SymbolObject, Value),
};

pub const ClassObject = struct {
    module: ModuleObject,
    superclass: ?*ClassObject,
    prepended_modules: std.ArrayList(*ModuleObject) = .empty,
    included_modules: std.ArrayList(*ModuleObject) = .empty,
};

pub const ArrayObject = struct {
    object: Object,
    elements: std.ArrayList(Value) = .empty,
};

pub const Value = struct {
    data: union(enum) {
        array: *ArrayObject,
        boolean: bool,
        class: *ClassObject,
        instance: *Object,
        integer: i64,
        module: *ModuleObject,
        nil: void,
        string: *StringObject,
        symbol: *SymbolObject,
    },

    pub fn isFrozen(self: Value) bool {
        return switch (self.data) {
            // Primitives are always frozen
            .integer, .string, .nil, .boolean => true,
            // Objects check their flags
            .symbol => |s| (s.object.flags & Object.FROZEN_FLAG) != 0,
            .module => |m| (m.object.flags & Object.FROZEN_FLAG) != 0,
            .class => |c| (c.module.object.flags & Object.FROZEN_FLAG) != 0,
            .instance => |i| (i.flags & Object.FROZEN_FLAG) != 0,
            .array => |a| (a.object.flags & Object.FROZEN_FLAG) != 0,
        };
    }

    pub fn freeze(self: *Value) void {
        switch (self.data) {
            .symbol => |s| s.object.flags |= Object.FROZEN_FLAG,
            .module => |m| m.object.flags |= Object.FROZEN_FLAG,
            .class => |c| c.object.flags |= Object.FROZEN_FLAG,
            .instance => |i| i.flags |= Object.FROZEN_FLAG,
            .array => |a| a.object.flags |= Object.FROZEN_FLAG,
            // Primitives are already frozen, do nothing
            else => {},
        }
    }

    pub fn nil() Value {
        return .{ .data = .nil };
    }

    pub fn boolean(value: bool) Value {
        return .{ .data = .{ .boolean = value } };
    }

    pub fn integer(value: i64) Value {
        return .{ .data = .{ .integer = value } };
    }

    pub fn format(self: Value, writer: *std.Io.Writer) !void {
        switch (self.data) {
            .integer => |i| try writer.print("{d}", .{i}),
            .string => |s| try writer.print("\"{s}\"", .{s}),
            .symbol => |s| try writer.print(":{s}", .{s.name}),
            .boolean => |b| try writer.print("{s}", .{if (b) "true" else "false"}),
            .nil => try writer.print("nil", .{}),
            .module => |m| try writer.print("<Module {s}>", .{m.name.name}),
            .class => |c| try writer.print("<Class {s}>", .{c.module.name.name}),
            .instance => |i| try writer.print("<{s} instance>", .{i.class.?.module.name.name}),
            .array => |a| {
                try writer.print("[", .{});
                for (a.elements.items, 0..) |elem, idx| {
                    if (idx > 0) try writer.print(", ", .{});
                    try elem.format(writer);
                }
                try writer.print("]", .{});
            },
        }
    }
};
