const std = @import("std");
const config = @import("config.zig");
const value = @import("../value.zig");
const vm_mod = @import("../vm.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Value = value.Value;

const cfg = config.RbConfig.init();

pub const ConfigEntry = struct {
    key: []const u8,
    value: []const u8,
};

pub const makefile_config_entries = [_]ConfigEntry{
    .{ .key = "MAJOR", .value = cfg.major },
    .{ .key = "MINOR", .value = cfg.minor },
    .{ .key = "TEENY", .value = cfg.teeny },
    .{ .key = "PATCHLEVEL", .value = cfg.patchlevel },
    .{ .key = "host_cpu", .value = cfg.host_cpu },
    .{ .key = "host_os", .value = cfg.host_os },
    .{ .key = "host_vendor", .value = cfg.host_vendor },
    .{ .key = "target_cpu", .value = cfg.target_cpu },
    .{ .key = "target_os", .value = cfg.target_os },
    .{ .key = "target_vendor", .value = cfg.target_vendor },
    .{ .key = "build_cpu", .value = cfg.build_cpu },
    .{ .key = "build_os", .value = cfg.build_os },
    .{ .key = "build_vendor", .value = cfg.build_vendor },
    .{ .key = "arch", .value = cfg.arch },
    .{ .key = "platform", .value = cfg.platform },
    .{ .key = "host", .value = "$(target)" },
    .{ .key = "target", .value = "$(target_cpu)-$(target_vendor)-$(target_os)" },
    .{ .key = "build", .value = "$(build_cpu)-$(build_vendor)-$(build_os)" },
    .{ .key = "RUBY_BASE_NAME", .value = cfg.ruby_base_name },
    .{ .key = "RUBY_INSTALL_NAME", .value = cfg.ruby_install_name },
    .{ .key = "RUBY_SO_NAME", .value = cfg.ruby_so_name },
    .{ .key = "RUBYW_BASE_NAME", .value = cfg.rubyw_base_name },
    .{ .key = "rubyw_install_name", .value = cfg.rubyw_install_name },
    .{ .key = "RUBY_VERSION_NAME", .value = cfg.ruby_version_name },
    .{ .key = "RUBY_PROGRAM_VERSION", .value = cfg.ruby_program_version },
    .{ .key = "RUBY_API_VERSION", .value = cfg.ruby_api_version },
    .{ .key = "ruby_version", .value = "$(MAJOR).$(MINOR).$(TEENY)" },
    .{ .key = "ruby_install_name", .value = "$(RUBY_BASE_NAME)" },
    .{ .key = "prefix", .value = cfg.prefix },
    .{ .key = "exec_prefix", .value = cfg.exec_prefix },
    .{ .key = "bindir", .value = cfg.bindir },
    .{ .key = "libdir", .value = cfg.libdir },
    .{ .key = "includedir", .value = cfg.includedir },
    .{ .key = "datadir", .value = cfg.datadir },
    .{ .key = "datarootdir", .value = cfg.datarootdir },
    .{ .key = "mandir", .value = cfg.mandir },
    .{ .key = "sysconfdir", .value = cfg.sysconfdir },
    .{ .key = "localstatedir", .value = cfg.localstatedir },
    .{ .key = "rubylibprefix", .value = cfg.rubylibprefix },
    .{ .key = "rubylibdir", .value = cfg.rubylibdir },
    .{ .key = "rubyarchdir", .value = cfg.rubyarchdir },
    .{ .key = "rubyhdrdir", .value = cfg.rubyhdrdir },
    .{ .key = "archdir", .value = "$(rubyarchdir)" },
    .{ .key = "sitedir", .value = cfg.sitedir },
    .{ .key = "sitelibdir", .value = cfg.sitelibdir },
    .{ .key = "sitearchdir", .value = cfg.sitearchdir },
    .{ .key = "sitearch", .value = cfg.sitearch },
    .{ .key = "vendordir", .value = cfg.vendordir },
    .{ .key = "vendorlibdir", .value = cfg.vendorlibdir },
    .{ .key = "vendorarchdir", .value = cfg.vendorarchdir },
    .{ .key = "SOEXT", .value = cfg.soext },
    .{ .key = "DLEXT", .value = cfg.dlext },
    .{ .key = "LIBEXT", .value = cfg.libext },
    .{ .key = "EXEEXT", .value = cfg.exeext },
    .{ .key = "OBJEXT", .value = cfg.objext },
    .{ .key = "EXECUTABLE_EXTS", .value = cfg.executable_exts },
    .{ .key = "ENABLE_SHARED", .value = cfg.enable_shared },
    .{ .key = "LIBRUBY", .value = cfg.libruby },
    .{ .key = "LIBRUBY_SO", .value = cfg.libruby_so },
    .{ .key = "LIBRUBY_A", .value = cfg.libruby_a },
    .{ .key = "LIBRUBY_SONAME", .value = cfg.libruby_soname },
    .{ .key = "LIBRUBY_RELATIVE", .value = cfg.libruby_relative },
    .{ .key = "LIBRUBYARG", .value = cfg.librubyarg },
    .{ .key = "LIBRUBYARG_SHARED", .value = cfg.librubyarg_shared },
    .{ .key = "LIBRUBYARG_STATIC", .value = cfg.librubyarg_static },
    .{ .key = "CC", .value = cfg.cc },
    .{ .key = "CXX", .value = cfg.cxx },
    .{ .key = "LD", .value = cfg.ld },
    .{ .key = "AR", .value = cfg.ar },
    .{ .key = "RANLIB", .value = cfg.ranlib },
    .{ .key = "STRIP", .value = cfg.strip },
    .{ .key = "NM", .value = cfg.nm },
    .{ .key = "OBJDUMP", .value = cfg.objdump },
    .{ .key = "OBJCOPY", .value = cfg.objcopy },
    .{ .key = "AS", .value = cfg.@"as" },
    .{ .key = "INSTALL", .value = cfg.install },
    .{ .key = "INSTALL_PROGRAM", .value = cfg.install_program },
    .{ .key = "INSTALL_SCRIPT", .value = cfg.install_script },
    .{ .key = "INSTALL_DATA", .value = cfg.install_data },
    .{ .key = "CP", .value = cfg.cp },
    .{ .key = "RM", .value = cfg.rm },
    .{ .key = "MKDIR_P", .value = cfg.mkdir_p },
    .{ .key = "MAKEDIRS", .value = cfg.makedirs },
    .{ .key = "LN_S", .value = cfg.ln_s },
    .{ .key = "GREP", .value = cfg.grep },
    .{ .key = "EGREP", .value = cfg.egrep },
    .{ .key = "PKG_CONFIG", .value = cfg.pkg_config },
    .{ .key = "SHELL", .value = cfg.shell },
    .{ .key = "PATH_SEPARATOR", .value = cfg.path_separator },
    .{ .key = "NULLCMD", .value = cfg.nullcmd },
    .{ .key = "CFLAGS", .value = cfg.cflags },
    .{ .key = "CXXFLAGS", .value = cfg.cxxflags },
    .{ .key = "LDFLAGS", .value = cfg.ldflags },
    .{ .key = "DLDFLAGS", .value = cfg.dldflags },
    .{ .key = "CCDLFLAGS", .value = cfg.ccdlflags },
    .{ .key = "ARCH_FLAG", .value = cfg.arch_flag },
    .{ .key = "optflags", .value = cfg.optflags },
    .{ .key = "debugflags", .value = cfg.debugflags },
    .{ .key = "warnflags", .value = cfg.warnflags },
    .{ .key = "LDSHARED", .value = cfg.ldshared },
    .{ .key = "LDSHAREDXX", .value = cfg.ldsharedxx },
    .{ .key = "DLDSHARED", .value = cfg.dldshared },
    .{ .key = "LINK_SO", .value = cfg.link_so },
    .{ .key = "STATIC", .value = cfg.static },
    .{ .key = "ALLOCA", .value = cfg.alloca },
    .{ .key = "POSTLINK", .value = cfg.postlink },
    .{ .key = "TRY_LINK", .value = cfg.try_link },
    .{ .key = "SOLIBS", .value = cfg.solibs },
    .{ .key = "MAINLIBS", .value = cfg.mainlibs },
    .{ .key = "LIBS", .value = cfg.libs },
    .{ .key = "DLDLIBS", .value = cfg.dldlibs },
    .{ .key = "COMMON_LIBS", .value = cfg.common_libs },
    .{ .key = "DLNOBJ", .value = cfg.dlnobj },
    .{ .key = "LIBPATHENV", .value = cfg.libpathenv },
    .{ .key = "PRELOADENV", .value = cfg.preloadenv },
    .{ .key = "RPATHFLAG", .value = cfg.rpathflag },
    .{ .key = "LIBPATHFLAG", .value = cfg.libpathflag },
    .{ .key = "libdirname", .value = cfg.libdirname },
    .{ .key = "EXTOUT", .value = cfg.exto },
    .{ .key = "ENCSTATIC", .value = cfg.encstatic },
    .{ .key = "EXTSTATIC", .value = cfg.extstatic },
    .{ .key = "PREP", .value = cfg.prep },
    .{ .key = "setup", .value = cfg.setup },
    .{ .key = "MAKEFILES", .value = cfg.makefiles },
    .{ .key = "INSTALL_STATIC_LIBRARY", .value = cfg.install_static_library },
    .{ .key = "ENABLE_DEBUG_ENV", .value = cfg.enable_debug_env },
    .{ .key = "CROSS_COMPILING", .value = cfg.cross_compiling },
    .{ .key = "TEST_RUNNABLE", .value = cfg.test_runnable },
    .{ .key = "RUBY_DEVEL", .value = cfg.ruby_devel },
    .{ .key = "HAVE_GIT", .value = cfg.have_git },
    .{ .key = "GIT", .value = cfg.git },
    .{ .key = "GCC", .value = cfg.gcc },
    .{ .key = "GNU_LD", .value = cfg.gnu_ld },
    .{ .key = "CARGO", .value = cfg.cargo },
    .{ .key = "RUSTC", .value = cfg.rustc },
    .{ .key = "YJIT_SUPPORT", .value = cfg.yjit_support },
    .{ .key = "RJIT_SUPPORT", .value = cfg.rjit_support },
    .{ .key = "PACKAGE", .value = cfg.package },
    .{ .key = "MANTYPE", .value = cfg.mantype },
    .{ .key = "RI_BASE_NAME", .value = cfg.ri_base_name },
    .{ .key = "ridir", .value = cfg.ridir },
    .{ .key = "ARFLAGS", .value = cfg.arflags },
    .{ .key = "CC_VERSION", .value = cfg.cc_version },
    .{ .key = "CC_VERSION_MESSAGE", .value = cfg.cc_version_message },
    .{ .key = "MKMF_VERBOSE", .value = cfg.mkmf_verbose },
    .{ .key = "configure_args", .value = cfg.configure_args },
    .{ .key = "CONFIGURE", .value = cfg.configure },
    .{ .key = "UNICODE_VERSION", .value = cfg.unicode_version },
    .{ .key = "UNICODE_EMOJI_VERSION", .value = cfg.unicode_emoji_version },
    .{ .key = "DEFS", .value = cfg.defs },
    .{ .key = "DOT", .value = cfg.dot },
    .{ .key = "DOXYGEN", .value = cfg.doxygen },
};

pub fn buildRbConfigModule(vm: *VM) VMError!Value {
    const rbconfig_sym = try vm.intern("RbConfig");
    const config_sym = try vm.intern("CONFIG");
    const topdir_sym = try vm.intern("TOPDIR");

    const rbconfig_val = try vm.newModule(rbconfig_sym);
    const rbconfig_module = rbconfig_val.toModuleObject();

    const conf_obj = try vm.createHash();
    const conf_val = Value.fromObject(&conf_obj.object);
    const conf = conf_val.toHashObject();

    for (makefile_config_entries) |entry| {
        try vm.hashSetEntry(conf, try vm.newString(entry.key, false), try vm.newString(entry.value, false));
    }

    for (conf.entries.items) |*conf_entry| {
        const expanded = expandValue(vm, conf_entry.value, conf_val) catch return error.Fatal;
        conf_entry.value = expanded;
    }

    rbconfig_module.constants.put(topdir_sym, .{ .value = Value.nil() }) catch return error.Fatal;
    rbconfig_module.constants.put(config_sym, .{ .value = conf_val }) catch return error.Fatal;

    vm.object_class.module.constants.put(rbconfig_sym, .{ .value = rbconfig_val }) catch return error.Fatal;

    return rbconfig_val;
}

pub fn expandValue(vm: *VM, val: Value, config_val: Value) VMError!Value {
    if (!val.isString()) return val;

    const str = val.toStringObject().str;
    if (str.len == 0) return val;

    const buf = vm.allocator.alloc(u8, str.len * 4 + 256) catch return error.Fatal;
    defer vm.allocator.free(buf);
    var buf_len: usize = 0;

    var i: usize = 0;
    while (i < str.len) {
        if (str[i] == '$' and i + 1 < str.len) {
            if (str[i + 1] == '$') {
                if (buf_len < buf.len) { buf[buf_len] = '$'; buf_len += 1; }
                i += 2;
                continue;
            }

            if (str[i + 1] == '(') {
                const end = std.mem.indexOfScalarPos(u8, str, i + 2, ')') orelse {
                    try appendToBuf(buf, &buf_len, str[i..]);
                    break;
                };
                const var_name = str[i + 2 .. end];
                const resolved = resolveConfigVar(vm, var_name, config_val) catch return error.Fatal;
                if (resolved) |r| {
                    try appendToBuf(buf, &buf_len, r.toStringObject().str);
                } else {
                    try appendToBuf(buf, &buf_len, str[i .. end + 1]);
                }
                i = end + 1;
                continue;
            }

            if (str[i + 1] == '{') {
                const end = std.mem.indexOfScalarPos(u8, str, i + 2, '}') orelse {
                    try appendToBuf(buf, &buf_len, str[i..]);
                    break;
                };
                const var_name = str[i + 2 .. end];
                const resolved = resolveConfigVar(vm, var_name, config_val) catch return error.Fatal;
                if (resolved) |r| {
                    try appendToBuf(buf, &buf_len, r.toStringObject().str);
                } else {
                    try appendToBuf(buf, &buf_len, str[i .. end + 1]);
                }
                i = end + 1;
                continue;
            }
        }
        if (buf_len < buf.len) { buf[buf_len] = str[i]; buf_len += 1; }
        i += 1;
    }

    return try vm.newString(buf[0..buf_len], val.isFrozen());
}

fn resolveConfigVar(vm: *VM, var_name: []const u8, config_val: Value) VMError!?Value {
    if (!config_val.isHash()) return null;

    const config_hash = config_val.toHashObject();
    const key = try vm.newString(var_name, false);
    const entry = try vm.hashGetEntry(config_hash, key);
    if (entry == null) return null;

    const entry_value = entry.?.value;
    if (!entry_value.isString()) return null;

    return expandValue(vm, entry_value, config_val) catch return error.Fatal;
}

fn appendToBuf(buf: []u8, buf_len: *usize, data: []const u8) VMError!void {
    if (buf_len.* + data.len > buf.len) return error.Fatal;
    @memcpy(buf[buf_len.* .. buf_len.* + data.len], data);
    buf_len.* += data.len;
}
