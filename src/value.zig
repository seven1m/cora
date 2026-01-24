const std = @import("std");
const prism = @import("prism.zig");
const bdwgc = @import("bdwgc");
const Chunk = @import("chunk.zig").Chunk;

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
};

pub const Method = union(enum) {
    chunk: *Chunk,
    builtin: *const fn (std.mem.Allocator, Value, []Value) RuntimeError!Value,
};

pub const Object = struct {
    const FROZEN_FLAG = 0x1;

    flags: u32,
    class: ?*ClassObject,
};

pub const SymbolObject = struct {
    object: Object,
    name: []const u8,
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
};

pub const Value = struct {
    data: union(enum) {
        string: []const u8,
        integer: i64,
        nil: void,
        boolean: bool,
        symbol: *SymbolObject,
        module: *ModuleObject,
        class: *ClassObject,
        instance: *Object,
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
        };
    }

    pub fn freeze(self: *Value) void {
        switch (self.data) {
            .symbol => |s| s.object.flags |= Object.FROZEN_FLAG,
            .module => |m| m.object.flags |= Object.FROZEN_FLAG,
            .class => |c| c.object.flags |= Object.FROZEN_FLAG,
            .instance => |i| i.flags |= Object.FROZEN_FLAG,
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

    pub fn frozenString(str: []const u8) Value {
        return .{ .data = .{ .string = str } };
    }

    pub fn integer(value: i64) Value {
        return .{ .data = .{ .integer = value } };
    }

    pub fn symbol(gc_allocator: std.mem.Allocator, str: []const u8) Value {
        const symbol_obj = gc_allocator.create(SymbolObject) catch unreachable;
        symbol_obj.* = .{
            .object = .{ .flags = Object.FROZEN_FLAG, .class = null },
            .name = str,
        };
        return .{ .data = .{ .symbol = symbol_obj } };
    }

    pub fn module(gc_allocator: std.mem.Allocator, name: *SymbolObject) Value {
        const module_obj = gc_allocator.create(ModuleObject) catch unreachable;
        module_obj.* = .{
            .object = .{ .flags = 0, .class = null },
            .name = name,
            .methods = std.AutoHashMap(*SymbolObject, Method).init(gc_allocator),
            .constants = std.AutoHashMap(*SymbolObject, Value).init(gc_allocator),
        };
        return .{ .data = .{ .module = module_obj } };
    }

    pub fn class(gc_allocator: std.mem.Allocator, name: *SymbolObject, superclass: ?*ClassObject) Value {
        const class_obj = gc_allocator.create(ClassObject) catch unreachable;
        class_obj.* = .{
            .superclass = superclass,
            .module = .{
                .object = .{ .flags = 0, .class = null },
                .name = name,
                .methods = std.AutoHashMap(*SymbolObject, Method).init(gc_allocator),
                .constants = std.AutoHashMap(*SymbolObject, Value).init(gc_allocator),
            },
        };
        return .{ .data = .{ .class = class_obj } };
    }

    pub fn instance(gc_allocator: std.mem.Allocator, class_obj: *ClassObject) Value {
        const obj = gc_allocator.create(Object) catch unreachable;
        obj.* = .{
            .flags = 0,
            .class = class_obj,
        };
        return .{ .data = .{ .instance = obj } };
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
        }
    }
};
