const std = @import("std");
const prism = @import("prism.zig");
const bdwgc = @import("bdwgc");
const Chunk = @import("chunk.zig").Chunk;
const VM = @import("vm.zig").VM;
const Method = @import("vm.zig").Method;

const encoding = @import("encoding.zig");
const Encoding = encoding.Encoding;
const ValidityState = encoding.ValidityState;

pub const Object = struct {
    pub const FROZEN_FLAG = 0x1;

    flags: u32,
    class: ?*ClassObject,
    singleton_class: ?*ClassObject,
    instance_variables: ?std.AutoHashMap(*SymbolObject, Value),
};

pub const SymbolObject = struct {
    object: Object,
    name: []const u8,
};

pub const StringObject = struct {
    object: Object,
    str: []const u8,
    encoding: Encoding = .{ .utf8 = .{} },
    validity: ValidityState = .unknown,
};

pub const EncodingObject = struct {
    object: Object,
    encoding: Encoding,
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

pub const HashEntry = struct {
    key: Value,
    value: Value,
};

pub const HashObject = struct {
    object: Object,
    map: std.AutoHashMap(u64, usize),
    entries: std.ArrayList(HashEntry) = .empty,
};

pub const ExceptionObject = struct {
    object: Object,
    message: *StringObject,
    backtrace: ?*ArrayObject,
    cause: ?*ExceptionObject,
};

pub const Block = @import("vm.zig").Block;

pub const ProcObject = struct {
    object: Object,
    block: Block,
};

pub const Value = struct {
    data: union(enum) {
        array: *ArrayObject,
        boolean: bool,
        class: *ClassObject,
        encoding: *EncodingObject,
        exception: *ExceptionObject,
        hash: *HashObject,
        instance: *Object,
        integer: i64,
        module: *ModuleObject,
        nil: void,
        proc: *ProcObject,
        string: *StringObject,
        symbol: *SymbolObject,
    },

    pub fn isFrozen(self: Value) bool {
        return switch (self.data) {
            // Primitives are always frozen
            .integer, .string, .nil, .boolean => true,
            // Encoding objects are always frozen (singletons)
            .encoding => true,
            // Objects check their flags
            .symbol => |s| (s.object.flags & Object.FROZEN_FLAG) != 0,
            .module => |m| (m.object.flags & Object.FROZEN_FLAG) != 0,
            .class => |c| (c.module.object.flags & Object.FROZEN_FLAG) != 0,
            .instance => |i| (i.flags & Object.FROZEN_FLAG) != 0,
            .array => |a| (a.object.flags & Object.FROZEN_FLAG) != 0,
            .exception => |e| (e.object.flags & Object.FROZEN_FLAG) != 0,
            .hash => |h| (h.object.flags & Object.FROZEN_FLAG) != 0,
            .proc => |p| (p.object.flags & Object.FROZEN_FLAG) != 0,
        };
    }

    pub fn freeze(self: *Value) void {
        switch (self.data) {
            .symbol => |s| s.object.flags |= Object.FROZEN_FLAG,
            .module => |m| m.object.flags |= Object.FROZEN_FLAG,
            .class => |c| c.object.flags |= Object.FROZEN_FLAG,
            .instance => |i| i.flags |= Object.FROZEN_FLAG,
            .array => |a| a.object.flags |= Object.FROZEN_FLAG,
            .exception => |e| e.object.flags |= Object.FROZEN_FLAG,
            .hash => |h| h.object.flags |= Object.FROZEN_FLAG,
            .proc => |p| p.object.flags |= Object.FROZEN_FLAG,
            // Primitives are already frozen, do nothing
            else => {},
        }
    }

    pub fn getObjectPointer(self: Value) ?*Object {
        return switch (self.data) {
            .class => |c| &c.module.object,
            .encoding => |e| &e.object,
            .module => |m| &m.object,
            .instance => |i| i,
            .string => |s| &s.object,
            .symbol => |s| &s.object,
            .array => |a| &a.object,
            .exception => |e| &e.object,
            .hash => |h| &h.object,
            .proc => |p| &p.object,
            .integer, .nil, .boolean => null,
        };
    }

    pub fn getSingletonClass(self: Value) ?*ClassObject {
        const obj_ptr = self.getObjectPointer();
        if (obj_ptr) |obj| {
            return obj.singleton_class;
        }
        return null;
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
            .encoding => |e| try writer.print("#<Encoding:{s}>", .{e.encoding.name()}),
            .instance => |i| try writer.print("<{s} instance>", .{i.class.?.module.name.name}),
            .array => |a| {
                try writer.print("[", .{});
                for (a.elements.items, 0..) |elem, idx| {
                    if (idx > 0) try writer.print(", ", .{});
                    try elem.format(writer);
                }
                try writer.print("]", .{});
            },
            .exception => |e| try writer.print("#<{s}: {s}>", .{ e.object.class.?.module.name.name, e.message.str }),
            .hash => |h| {
                try writer.print("{", .{});
                for (h.entries.items, 0..) |entry, idx| {
                    if (idx > 0) try writer.print(", ", .{});
                    try entry.key.format(writer);
                    try writer.print("=>", .{});
                    try entry.value.format(writer);
                }
                try writer.print("}", .{});
            },
            .proc => |p| try writer.print("#<Proc:0x{x}>", .{@intFromPtr(p)}),
        }
    }

    pub fn hash(self: Value) u64 {
        return switch (self.data) {
            .integer => |i| @bitCast(@as(i64, i)),
            .boolean => |b| if (b) 1 else 0,
            .nil => 0,
            .symbol => |s| @intFromPtr(s),
            .string => |s| std.hash.Wyhash.hash(0, s.str),
            else => @intFromPtr(self.getObjectPointer() orelse return 0),
        };
    }

    pub fn eql(self: Value, other: Value) bool {
        const self_tag = @as(std.meta.Tag(@TypeOf(self.data)), self.data);
        const other_tag = @as(std.meta.Tag(@TypeOf(other.data)), other.data);

        if (self_tag != other_tag) return false;

        return switch (self.data) {
            .integer => |i| i == other.data.integer,
            .boolean => |b| b == other.data.boolean,
            .nil => true,
            .symbol => |s| s == other.data.symbol,
            .string => |s| std.mem.eql(u8, s.str, other.data.string.str),
            else => self.hash() == other.hash(),
        };
    }
};
