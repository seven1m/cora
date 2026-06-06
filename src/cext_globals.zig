var current_vm_opaque: ?*anyopaque = null;

pub fn setCurrentVM(vm_ptr: *anyopaque) void {
    current_vm_opaque = vm_ptr;
}

pub fn getCurrentVM() *anyopaque {
    return current_vm_opaque orelse @panic("cext: no current VM set");
}
