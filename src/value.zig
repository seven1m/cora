const std = @import("std");
const prism = @import("prism.zig");
const bdwgc = @import("bdwgc");
const Chunk = @import("chunk.zig").Chunk;

pub const ModuleValue = struct {
    name: []const u8,
    methods: std.StringHashMap(*Chunk),
};

pub const ClassValue = struct {
    name: []const u8,
    superclass: ?*ClassValue,
    methods: std.StringHashMap(*Chunk),
};

pub const InstanceValue = struct {
    class: *ClassValue,
};

pub const Value = struct {
    frozen: bool,
    data: union(enum) {
        string: []const u8,
        integer: i64,
        nil: void,
        boolean: bool,
        symbol: []const u8,
        module: *ModuleValue,
        class: *ClassValue,
        instance: *InstanceValue,
    },

    pub fn nil() Value {
        return .{ .frozen = true, .data = .nil };
    }

    pub fn boolean(value: bool) Value {
        return .{ .frozen = true, .data = .{ .boolean = value } };
    }

    pub fn frozenString(str: []const u8) Value {
        return .{ .frozen = true, .data = .{ .string = str } };
    }

    pub fn integer(value: i64) Value {
        return .{ .frozen = true, .data = .{ .integer = value } };
    }

    pub fn symbol(str: []const u8) Value {
        return .{ .frozen = true, .data = .{ .symbol = str } };
    }

    pub fn module(gc_allocator: std.mem.Allocator, name: []const u8) Value {
        const module_value = gc_allocator.create(ModuleValue) catch unreachable;
        module_value.* = .{
            .name = name,
            .methods = std.StringHashMap(*Chunk).init(gc_allocator),
        };
        return .{ .frozen = false, .data = .{ .module = module_value } };
    }

    pub fn class(gc_allocator: std.mem.Allocator, name: []const u8, superclass: ?*ClassValue) Value {
        const class_value = gc_allocator.create(ClassValue) catch unreachable;
        class_value.* = .{
            .name = name,
            .superclass = superclass,
            .methods = std.StringHashMap(*Chunk).init(gc_allocator),
        };
        return .{ .frozen = false, .data = .{ .class = class_value } };
    }

    pub fn instance(gc_allocator: std.mem.Allocator, class_value: *ClassValue) Value {
        const instance_value = gc_allocator.create(InstanceValue) catch unreachable;
        instance_value.* = .{
            .class = class_value,
        };
        return .{ .frozen = false, .data = .{ .instance = instance_value } };
    }

    pub fn format(self: Value, writer: *std.Io.Writer) !void {
        switch (self.data) {
            .integer => |i| try writer.print("{d}", .{i}),
            .string => |s| try writer.print("\"{s}\"", .{s}),
            .symbol => |s| try writer.print(":{s}", .{s}),
            .boolean => |b| try writer.print("{s}", .{if (b) "true" else "false"}),
            .nil => try writer.print("nil", .{}),
            .module => |m| try writer.print("<Module {s}>", .{m.name}),
            .class => |c| try writer.print("<Class {s}>", .{c.name}),
            .instance => |i| try writer.print("<{s} instance>", .{i.class.name}),
        }
    }
};
