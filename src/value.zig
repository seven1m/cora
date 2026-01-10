const std = @import("std");
const prism = @import("prism.zig");
const bdwgc = @import("bdwgc");

pub const ModuleValue = struct {
    name: []const u8,
    methods: std.StringHashMap(*prism.DefNode),
};

pub const ClassValue = struct {
    name: []const u8,
    superclass: ?*ClassValue,
    methods: std.StringHashMap(*prism.DefNode),
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
        symbol: []const u8,
        module: *ModuleValue,
        class: *ClassValue,
        instance: *InstanceValue,
    },

    pub fn nil() Value {
        return .{ .frozen = true, .data = .nil };
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
            .methods = std.StringHashMap(*prism.DefNode).init(gc_allocator),
        };
        return .{ .frozen = false, .data = .{ .module = module_value } };
    }

    pub fn class(gc_allocator: std.mem.Allocator, name: []const u8, superclass: ?*ClassValue) Value {
        const class_value = gc_allocator.create(ClassValue) catch unreachable;
        class_value.* = .{
            .name = name,
            .superclass = superclass,
            .methods = std.StringHashMap(*prism.DefNode).init(gc_allocator),
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
};
