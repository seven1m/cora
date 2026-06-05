const value = @import("value.zig");

const Value = value.Value;
const ModuleObject = value.ModuleObject;
const ClassObject = value.ClassObject;

pub fn isVisibleAncestor(node: *ModuleObject) bool {
    return node.object.type_tag != .iclass or !node.is_origin_iclass;
}

pub fn visibleModule(node: *ModuleObject) *ModuleObject {
    if (node.object.type_tag == .iclass and node.origin.is_origin_iclass) {
        return node.origin.includer orelse node.origin;
    }
    if (node.object.type_tag == .iclass) {
        return node.origin;
    }
    return node;
}

pub fn methodTableOwner(node: *ModuleObject) *ModuleObject {
    if (node.object.type_tag == .iclass) {
        return node.origin;
    }
    return node;
}

pub fn visibleValue(node: *ModuleObject) Value {
    return Value.fromObject(&visibleModule(node).object);
}

pub fn nextVisibleClass(start: ?*ModuleObject) ?*ClassObject {
    var current = start;
    while (current) |node| : (current = node.super) {
        if (node.object.type_tag == .class) {
            return @fieldParentPtr("module", node);
        }
    }
    return null;
}

pub fn sameOrigin(a: *ModuleObject, b: *ModuleObject) bool {
    return a.origin == b.origin;
}
