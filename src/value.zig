const std = @import("std");
const prism = @import("prism.zig");
const bdwgc = @import("bdwgc");
const vm = @import("vm.zig");
const Chunk = @import("chunk.zig").Chunk;
const VM = vm.VM;
const VMError = vm.VMError;
const Method = vm.Method;
const Block = vm.Block;
const FiberValueStack = vm.FiberValueStack;
const FiberFrameStack = vm.FiberFrameStack;
const FiberEnvironmentStack = vm.FiberEnvironmentStack;
const FiberCoro = vm.FiberCoro;
const onigmo = @import("onigmo.zig");

const encoding = @import("encoding.zig");
const Encoding = encoding.Encoding;
const ValidityState = encoding.ValidityState;

pub const MethodVisibility = enum {
    public,
    private,
    protected,
};

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
    scope_module: union(enum) {
        module: *ModuleObject,
        class: *ClassObject,
    },
    parent: ?*LexicalScope,
    default_method_visibility: MethodVisibility = .public,
    module_function_mode: bool = false,

    pub fn getModule(self: *LexicalScope) *ModuleObject {
        switch (self.scope_module) {
            .module => |m| return m,
            .class => |c| return &c.module,
        }
    }
};

pub const ModuleObject = struct {
    object: Object,
    name: *SymbolObject,
    methods: std.AutoHashMap(*SymbolObject, MethodEntry),
    constants: std.AutoHashMap(*SymbolObject, Value),
    class_variables: std.AutoHashMap(*SymbolObject, Value),
};

pub const MethodEntry = struct {
    method: Method,
    visibility: MethodVisibility = .public,
};

pub const ObjectType = enum {
    instance,
    array,
    hash,
    range,
    fiber,
    io,
};

pub const ClassObject = struct {
    module: ModuleObject,
    superclass: ?*ClassObject,
    object_type: ObjectType = .instance,
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

pub const RangeObject = struct {
    object: Object,
    begin: Value,
    end: Value,
    exclude_end: bool,
};

pub const ExceptionObject = struct {
    object: Object,
    message: *StringObject,
    backtrace: ?*ArrayObject,
    cause: ?*ExceptionObject,
};

pub const ProcObject = struct {
    object: Object,
    block: Block,
};

pub const FiberObject = struct {
    pub const CoroEvent = enum {
        none,
        yielded,
        returned,
        raised,
    };

    object: Object,
    state: enum { created, running, suspended, terminated },
    block: ?Block,
    stack: FiberValueStack,
    frames: FiberFrameStack,
    env_stack: FiberEnvironmentStack,
    current_lexical_scope: ?*LexicalScope = null,
    caller: ?*FiberObject = null,
    coro: ?*FiberCoro = null,
    coro_event: CoroEvent = .none,
    coro_result: Value = Value.nil(),
    coro_exception: ?*ExceptionObject = null,
    first_resume_args: [256]Value = undefined,
    first_resume_argc: usize = 0,
    owner_vm: *VM,
};

pub const IoObject = struct {
    object: Object,
    fd: i32,
    owns_fd: bool,
    closed: bool = false,
    readable: bool,
    writable: bool,
    append: bool,
};

pub const RegexpObject = struct {
    object: Object,
    pattern: []const u8,
    options: u16,
    regex: onigmo.OnigRegex,
};

pub const MatchDataObject = struct {
    object: Object,
    regexp: *RegexpObject,
    source: *StringObject,
    captures: std.ArrayList(Value) = .empty,
    begin_byte_offsets: std.ArrayList(i64) = .empty,
    end_byte_offsets: std.ArrayList(i64) = .empty,
};

pub const Value = struct {
    data: union(enum) {
        array: *ArrayObject,
        boolean: bool,
        class: *ClassObject,
        encoding: *EncodingObject,
        exception: *ExceptionObject,
        fiber: *FiberObject,
        hash: *HashObject,
        io: *IoObject,
        instance: *Object,
        integer: i64,
        float: f64,
        module: *ModuleObject,
        nil: void,
        match_data: *MatchDataObject,
        proc: *ProcObject,
        range: *RangeObject,
        regexp: *RegexpObject,
        string: *StringObject,
        symbol: *SymbolObject,
    },

    pub fn isFrozen(self: Value) bool {
        return switch (self.data) {
            // Primitives are always frozen
            .integer, .float, .nil, .boolean => true,
            // Encoding objects are always frozen (singletons)
            .encoding => true,
            // Regexp literals are always frozen (like in Ruby)
            .regexp => true,
            // Objects check their flags
            .string => |s| (s.object.flags & Object.FROZEN_FLAG) != 0,
            .symbol => |s| (s.object.flags & Object.FROZEN_FLAG) != 0,
            .module => |m| (m.object.flags & Object.FROZEN_FLAG) != 0,
            .class => |c| (c.module.object.flags & Object.FROZEN_FLAG) != 0,
            .instance => |i| (i.flags & Object.FROZEN_FLAG) != 0,
            .array => |a| (a.object.flags & Object.FROZEN_FLAG) != 0,
            .exception => |e| (e.object.flags & Object.FROZEN_FLAG) != 0,
            .fiber => |f| (f.object.flags & Object.FROZEN_FLAG) != 0,
            .hash => |h| (h.object.flags & Object.FROZEN_FLAG) != 0,
            .io => |io| (io.object.flags & Object.FROZEN_FLAG) != 0,
            .match_data => |m| (m.object.flags & Object.FROZEN_FLAG) != 0,
            .proc => |p| (p.object.flags & Object.FROZEN_FLAG) != 0,
            .range => |r| (r.object.flags & Object.FROZEN_FLAG) != 0,
        };
    }

    pub fn freeze(self: *Value) void {
        switch (self.data) {
            .string => |s| s.object.flags |= Object.FROZEN_FLAG,
            .symbol => |s| s.object.flags |= Object.FROZEN_FLAG,
            .module => |m| m.object.flags |= Object.FROZEN_FLAG,
            .class => |c| c.module.object.flags |= Object.FROZEN_FLAG,
            .instance => |i| i.flags |= Object.FROZEN_FLAG,
            .array => |a| a.object.flags |= Object.FROZEN_FLAG,
            .exception => |e| e.object.flags |= Object.FROZEN_FLAG,
            .fiber => |f| f.object.flags |= Object.FROZEN_FLAG,
            .hash => |h| h.object.flags |= Object.FROZEN_FLAG,
            .io => |io| io.object.flags |= Object.FROZEN_FLAG,
            .match_data => |m| m.object.flags |= Object.FROZEN_FLAG,
            .proc => |p| p.object.flags |= Object.FROZEN_FLAG,
            .range => |r| r.object.flags |= Object.FROZEN_FLAG,
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
            .fiber => |f| &f.object,
            .hash => |h| &h.object,
            .io => |io| &io.object,
            .match_data => |m| &m.object,
            .proc => |p| &p.object,
            .range => |r| &r.object,
            .regexp => |r| &r.object,
            .integer, .float, .nil, .boolean => null,
        };
    }

    pub fn getSingletonClass(self: Value) ?*ClassObject {
        const obj_ptr = self.getObjectPointer();
        if (obj_ptr) |obj| {
            return obj.singleton_class;
        }
        return null;
    }

    pub fn getModuleObject(self: Value) ?*ModuleObject {
        return switch (self.data) {
            .class => |c| &c.module,
            .module => |m| m,
            else => null,
        };
    }

    pub fn getModuleMethods(self: Value) ?*std.AutoHashMap(*SymbolObject, MethodEntry) {
        const module_obj = self.getModuleObject() orelse return null;
        return &module_obj.methods;
    }

    pub fn objectId(self: Value) i64 {
        return if (self.getObjectPointer()) |ptr| blk: {
            break :blk @intCast(@intFromPtr(ptr));
        } else switch (self.data) {
            .integer => |i| (i << 1) | 1,
            .float => |f| @bitCast(f),
            .boolean => |b| if (b) 20 else 0,
            .nil => 8,
            else => unreachable,
        };
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

    pub fn float(value: f64) Value {
        return .{ .data = .{ .float = value } };
    }

    pub fn is_truthy(self: Value) bool {
        return switch (self.data) {
            .nil => false,
            .boolean => self.data.boolean,
            else => true,
        };
    }

    pub fn coerceToStringValue(self: Value, vm_instance: *VM, type_error_message: []const u8) VMError!Value {
        if (self.data == .string) {
            return self;
        }

        const to_str_sym = try vm_instance.intern("to_str");
        const has_to_str = (try vm_instance.findMethod(self, to_str_sym)) != null;
        if (!has_to_str) {
            const exc = try vm_instance.createException(vm_instance.type_error_class, type_error_message);
            vm_instance.pending_exception = exc;
            return error.Unwind;
        }

        const coerced = try vm_instance.callMethodByName(self, "to_str", &[_]Value{}, null);
        if (coerced.data != .string) {
            const exc = try vm_instance.createException(vm_instance.type_error_class, type_error_message);
            vm_instance.pending_exception = exc;
            return error.Unwind;
        }

        return coerced;
    }

    pub fn coerceToStr(self: Value, vm_instance: *VM, type_error_message: []const u8) VMError![]const u8 {
        const coerced = try self.coerceToStringValue(vm_instance, type_error_message);
        return coerced.data.string.str;
    }

    pub fn coerceToMatchSource(self: Value, vm_instance: *VM) VMError!?Value {
        switch (self.data) {
            .nil => return null,
            .string => return self,
            .symbol => |sym| return try vm_instance.newString(sym.name, false),
            else => {},
        }

        return try self.coerceToStringValue(vm_instance, "no implicit conversion into String");
    }

    pub fn format(self: Value, writer: *std.Io.Writer) !void {
        switch (self.data) {
            .integer => |i| try writer.print("{d}", .{i}),
            .float => |f| try writer.print("{d}", .{f}),
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
            .fiber => |f| try writer.print("#<Fiber:0x{x}>", .{@intFromPtr(f)}),
            .io => |io| try writer.print("#<IO:fd {d}>", .{io.fd}),
            .match_data => |m| {
                if (m.captures.items.len == 0 or m.captures.items[0].data != .string) {
                    try writer.print("#<MatchData>", .{});
                } else {
                    try writer.print("#<MatchData {s}>", .{m.captures.items[0].data.string.str});
                }
            },
            .range => |_| try writer.print("#<Range>", .{}),
            .regexp => |r| try writer.print("/{s}/", .{r.pattern}),
        }
    }

    pub fn hash(self: Value) u64 {
        return switch (self.data) {
            .integer => |i| @bitCast(@as(i64, i)),
            .float => |f| @bitCast(f),
            .boolean => |b| if (b) 1 else 0,
            .nil => 0,
            .symbol => |s| @intFromPtr(s),
            .string => |s| std.hash.Wyhash.hash(0, s.str),
            .regexp => |r| std.hash.Wyhash.hash(@as(u64, r.options), r.pattern),
            else => @intFromPtr(self.getObjectPointer() orelse return 0),
        };
    }

    pub fn eql(self: Value, other: Value) bool {
        const self_tag = @as(std.meta.Tag(@TypeOf(self.data)), self.data);
        const other_tag = @as(std.meta.Tag(@TypeOf(other.data)), other.data);

        if (self_tag != other_tag) return false;

        return switch (self.data) {
            .integer => |i| i == other.data.integer,
            .float => |f| f == other.data.float,
            .boolean => |b| b == other.data.boolean,
            .nil => true,
            .symbol => |s| s == other.data.symbol,
            .string => |s| std.mem.eql(u8, s.str, other.data.string.str),
            .regexp => |r| std.mem.eql(u8, r.pattern, other.data.regexp.pattern) and r.options == other.data.regexp.options,
            else => self.hash() == other.hash(),
        };
    }
};
