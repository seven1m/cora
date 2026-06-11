const std = @import("std");
const builtin = @import("builtin");
const version = @import("../version.zig");

pub const RbConfig = struct {
    ruby_engine: []const u8 = "cora",
    ruby_version: []const u8 = version.ruby_version,
    ruby_patch: []const u8 = version.ruby_patch,
    major: []const u8,
    minor: []const u8,
    teeny: []const u8,
    patchlevel: []const u8 = "0",

    host_cpu: []const u8,
    host_os: []const u8,
    host_vendor: []const u8 = "unknown",

    prefix: []const u8 = "/usr",
    exec_prefix: []const u8 = "$(prefix)",
    bindir: []const u8 = "$(exec_prefix)/bin",
    libdir: []const u8 = "$(exec_prefix)/lib",
    includedir: []const u8 = "$(prefix)/include",
    datadir: []const u8 = "$(datarootdir)",
    datarootdir: []const u8 = "$(prefix)/share",
    mandir: []const u8 = "$(datarootdir)/man",
    sysconfdir: []const u8 = "$(prefix)/etc",
    localstatedir: []const u8 = "$(prefix)/var",
    sharedstatedir: []const u8 = "$(prefix)/com",
    runstatedir: []const u8 = "$(localstatedir)/run",
    libexecdir: []const u8 = "$(exec_prefix)/libexec",
    sbindir: []const u8 = "$(exec_prefix)/sbin",
    oldincludedir: []const u8 = "/usr/include",
    psdir: []const u8 = "$(docdir)",
    pdfdir: []const u8 = "$(docdir)",
    dvidir: []const u8 = "$(docdir)",
    htmldir: []const u8 = "$(docdir)",
    infodir: []const u8 = "$(datarootdir)/info",
    docdir: []const u8 = "$(datarootdir)/doc/$(PACKAGE)",
    localedir: []const u8 = "$(datarootdir)/locale",

    ruby_base_name: []const u8 = "cora",
    ruby_install_name: []const u8 = "$(RUBY_BASE_NAME)",
    ruby_so_name: []const u8 = "$(RUBY_BASE_NAME)",
    rubyw_base_name: []const u8 = "rubyw",
    rubyw_install_name: []const u8 = "",
    ruby_version_name: []const u8 = "$(RUBY_BASE_NAME)-$(ruby_version)",
    ruby_program_version: []const u8 = "$(MAJOR).$(MINOR).$(TEENY)",
    ruby_api_version: []const u8 = "$(MAJOR).$(MINOR)",
    ruby_search_path: []const u8 = "",

    rubylibprefix: []const u8 = "$(libdir)/$(RUBY_BASE_NAME)",
    rubylibdir: []const u8 = "$(rubylibprefix)/$(ruby_version)",
    rubyarchdir: []const u8 = "$(rubylibdir)/$(arch)",
    rubysitearchprefix: []const u8 = "$(rubylibprefix)/$(sitearch)",
    rubyarchprefix: []const u8 = "$(rubylibprefix)/$(arch)",
    rubyhdrdir: []const u8 = "$(includedir)/$(RUBY_VERSION_NAME)",
    rubyarchhdrdir: []const u8 = "$(rubyhdrdir)/$(arch)",

    sitedir: []const u8 = "$(rubylibprefix)/site_ruby",
    sitelibdir: []const u8 = "$(sitedir)/$(ruby_version)",
    sitearchdir: []const u8 = "$(sitelibdir)/$(sitearch)",
    sitearch: []const u8 = "$(arch)",
    sitearchincludedir: []const u8 = "$(includedir)/$(sitearch)",
    sitearchlibdir: []const u8 = "$(libdir)/$(sitearch)",
    sitehdrdir: []const u8 = "$(rubyhdrdir)/site_ruby",
    sitearchhdrdir: []const u8 = "$(sitehdrdir)/$(sitearch)",

    vendordir: []const u8 = "$(rubylibprefix)/vendor_ruby",
    vendorlibdir: []const u8 = "$(vendordir)/$(ruby_version)",
    vendorarchdir: []const u8 = "$(vendorlibdir)/$(sitearch)",
    vendorhdrdir: []const u8 = "$(rubyhdrdir)/vendor_ruby",
    vendorarchhdrdir: []const u8 = "$(vendorhdrdir)/$(sitearch)",

    arch: []const u8,
    target_cpu: []const u8,
    target_os: []const u8,
    target_vendor: []const u8 = "unknown",
    host_cpu_dup: []const u8,
    host_os_dup: []const u8,
    host_vendor_dup: []const u8 = "unknown",
    build_cpu: []const u8,
    build_os: []const u8,
    build_vendor: []const u8 = "pc",
    platform: []const u8,

    soext: []const u8,
    dlext: []const u8,
    libext: []const u8 = "a",
    exeext: []const u8 = "",
    objext: []const u8 = "o",
    asmext: []const u8 = "S",
    executable_exts: []const u8 = "",

    enable_shared: []const u8 = "no",
    libruby: []const u8 = "libcora-static.a",
    libruby_so: []const u8 = "libcora.$(SOEXT).$(RUBY_PROGRAM_VERSION)",
    libruby_a: []const u8 = "libcora-static.a",
    libruby_soname: []const u8 = "libcora.$(SOEXT).$(RUBY_API_VERSION)",
    libruby_aliases: []const u8 = "libcora.$(SOEXT)",
    libruby_relative: []const u8 = "no",
    librubyarg: []const u8 = "$(LIBRUBYARG_STATIC)",
    librubyarg_shared: []const u8 = "-Wl,-rpath,$(libdir) -L$(libdir)",
    librubyarg_static: []const u8 = "-Wl,-rpath,$(libdir) -L$(libdir) $(MAINLIBS)",
    libruby_lib_version: []const u8 = "",
    libruby_lib_version_style: []const u8 = "3\t/* full */",
    ruby_so_name_dup: []const u8 = "cora",

    cc: []const u8 = "gcc",
    cxx: []const u8 = "g++",
    ld: []const u8 = "ld",
    ar: []const u8 = "ar",
    ranlib: []const u8 = "gcc-ranlib",
    strip: []const u8 = "strip",
    nm: []const u8 = "gcc-nm",
    objdump: []const u8 = "objdump",
    objcopy: []const u8 = "objcopy",
    @"as": []const u8 = "as",
    install: []const u8 = "/usr/bin/install -c",
    install_program: []const u8 = "$(INSTALL)",
    install_script: []const u8 = "$(INSTALL)",
    install_data: []const u8 = "$(INSTALL) -m 644",
    cp: []const u8 = "cp",
    rm: []const u8 = "rm -f",
    rmall: []const u8 = "rm -fr",
    rmdir: []const u8 = "rmdir --ignore-fail-on-non-empty",
    rmdirs: []const u8 = "rmdir --ignore-fail-on-non-empty -p",
    mkdir_p: []const u8 = "/usr/bin/mkdir -p",
    makedirs: []const u8 = "/usr/bin/mkdir -p",
    ln_s: []const u8 = "ln -s",
    grep: []const u8 = "/usr/bin/grep",
    egrep: []const u8 = "/usr/bin/grep -E",
    pkg_config: []const u8 = "pkg-config",
    chdir: []const u8 = "cd -P",
    shell: []const u8 = "/bin/bash",
    path_separator: []const u8 = ":",
    nullcmd: []const u8 = ":",
    set_make: []const u8 = "",

    cflags: []const u8 = "$(optflags) $(debugflags) $(warnflags)",
    cppflags: []const u8 = "",
    cxxflags: []const u8 = "",
    ldflags: []const u8 = "-L.",
    dldflags: []const u8 = "",
    extdldflags: []const u8 = "",
    extldflags: []const u8 = "",
    ccdlflags: []const u8 = "-fPIC",
    arch_flag: []const u8 = "",
    optflags: []const u8 = "-O3",
    debugflags: []const u8 = "-g",
    warnflags: []const u8 = "-Wall -Wextra",
    hardenflags: []const u8 = "",
    strict_warnflags: []const u8 = "",
    werrorflag: []const u8 = "",
    incflags: []const u8 = "",

    outflag: []const u8 = "-o ",
    coutflag: []const u8 = "-o ",
    cppoutfile: []const u8 = "-o conftest.i",
    csrcflag: []const u8 = "",

    ldshared: []const u8 = "$(CC) -shared",
    ldsharedxx: []const u8 = "$(CXX) -shared",
    dldshared: []const u8 = "$(CC) -shared",
    link_so: []const u8 = "\n$(POSTLINK)",
    static: []const u8 = "",
    alloca: []const u8 = "",
    postlink: []const u8 = ":",
    try_link: []const u8 = "",
    try_header: []const u8 = "",

    solibs: []const u8 = "$(MAINLIBS)",
    mainlibs: []const u8 = "-ldl -lm -lpthread",
    libs: []const u8 = "-lm -lpthread",
    dldlibs: []const u8 = "-lc",
    common_libs: []const u8 = "",
    common_headers: []const u8 = "",
    common_macros: []const u8 = "",
    dlnobj: []const u8 = "dln.o",

    libpathenv: []const u8,
    preloadenv: []const u8,
    rpathflag: []const u8,
    libpathflag: []const u8,

    libdirname: []const u8 = "libdir",
    exto: []const u8 = ".ext",
    encstatic: []const u8 = "",
    extstatic: []const u8 = "",
    builtin_transsrcs: []const u8 = "",
    prep: []const u8 = "miniruby$(EXEEXT)",
    setup: []const u8 = "Setup",
    makefiles: []const u8 = "Makefile GNUmakefile",

    install_static_library: []const u8 = "yes",
    enable_debug_env: []const u8 = "no",
    cross_compiling: []const u8 = "no",
    test_runnable: []const u8 = "yes",
    ruby_devel: []const u8 = "",
    have_git: []const u8 = "yes",
    git: []const u8 = "git",
    gcc: []const u8 = "yes",
    gnu_ld: []const u8 = "yes",
    cargo: []const u8 = "",
    rustc: []const u8 = "no",
    yjit_support: []const u8 = "no",
    rjit_support: []const u8 = "no",
    cargo_build_args: []const u8 = "",
    yjit_obj: []const u8 = "",
    yjit_libs: []const u8 = "",
    wasmopt: []const u8 = "",
    wasmoptflags: []const u8 = "",
    use_llvm_windres: []const u8 = "",
    platform_dir: []const u8 = "",
    coroutine_type: []const u8 = "",
    thread_model: []const u8 = "pthread",
    symbol_prefix: []const u8 = "",
    export_prefix: []const u8 = "",
    cc_wrapper: []const u8 = "",
    install_doc: []const u8 = "no",
    package: []const u8 = "cora",
    package_name: []const u8 = "",
    package_tarname: []const u8 = "",
    package_version: []const u8 = "",
    package_string: []const u8 = "",
    package_bugreport: []const u8 = "",
    package_url: []const u8 = "",
    mantype: []const u8 = "doc",
    ri_base_name: []const u8 = "ri",
    ridir: []const u8 = "$(datarootdir)/$(RI_BASE_NAME)",
    shared_gc_dir: []const u8 = "",
    dllwrap: []const u8 = "",
    windres: []const u8 = "",
    dsymutil: []const u8 = "",
    codesign: []const u8 = "",
    cleanlibs: []const u8 = "",
    arflags: []const u8 = "rcD ",
    cc_version: []const u8 = "$(CC) --version",
    cc_version_message: []const u8 = "gcc",
    mkmf_verbose: []const u8 = "0",
    install_static_library_2: []const u8 = "yes",
    universal_ints: []const u8 = "",
    universal_archnames: []const u8 = "",
    configure_args: []const u8 = "",
    configure: []const u8 = "configure",
    dstroot: []const u8 = "",
    archfile: []const u8 = "",
    echo_t: []const u8 = "",
    echo_n: []const u8 = "-n",
    echo_c: []const u8 = "",
    defs: []const u8 = "",
    dot: []const u8 = "dot",
    doxygen: []const u8 = "",
    target_alias: []const u8 = "",
    host_alias: []const u8 = "$(target_alias)",
    build_alias: []const u8 = "",
    unicode_version: []const u8 = "15.0.0",
    unicode_emoji_version: []const u8 = "15.0",

    destdir: []const u8 = "",

    pub fn init() RbConfig {
        const host_os_str = hostOs();
        const target_arch_str = @tagName(builtin.cpu.arch);
        const ruby_platform_str = comptime std.fmt.comptimePrint("{s}-{s}", .{ target_arch_str, @tagName(builtin.os.tag) });

        var parts = std.mem.splitScalar(u8, version.ruby_version, '.');
        const maj = parts.first();
        const min = parts.next() orelse "0";
        const teen = parts.next() orelse "0";

        return RbConfig{
            .major = maj,
            .minor = min,
            .teeny = teen,
            .host_cpu = target_arch_str,
            .host_os = host_os_str,
            .arch = ruby_platform_str,
            .target_cpu = target_arch_str,
            .target_os = host_os_str,
            .host_cpu_dup = target_arch_str,
            .host_os_dup = host_os_str,
            .build_cpu = target_arch_str,
            .build_os = comptime std.fmt.comptimePrint("{s}-gnu", .{@tagName(builtin.os.tag)}),
            .platform = ruby_platform_str,
            .soext = sharedLibraryExtension(),
            .dlext = sharedLibraryExtension(),
            .libpathenv = libPathEnv(),
            .preloadenv = preloadEnv(),
            .rpathflag = rpathFlag(),
            .libpathflag = libPathFlag(),
        };
    }
};

fn hostOs() []const u8 {
    return switch (builtin.os.tag) {
        .linux => "linux",
        .macos => "darwin",
        .windows => "mswin",
        else => @tagName(builtin.os.tag),
    };
}

fn sharedLibraryExtension() []const u8 {
    return switch (builtin.os.tag) {
        .windows => "dll",
        .macos => "bundle",
        else => "so",
    };
}

fn libPathEnv() []const u8 {
    return switch (builtin.os.tag) {
        .windows => "PATH",
        .macos => "DYLD_LIBRARY_PATH",
        else => "LD_LIBRARY_PATH",
    };
}

fn preloadEnv() []const u8 {
    return switch (builtin.os.tag) {
        .macos => "DYLD_INSERT_LIBRARIES",
        else => "LD_PRELOAD",
    };
}

fn rpathFlag() []const u8 {
    return switch (builtin.os.tag) {
        .macos => "-Wl,-rpath,%1$-s",
        else => "-Wl,-rpath,%1$-s",
    };
}

fn libPathFlag() []const u8 {
    return switch (builtin.os.tag) {
        .windows => "-libpath:%1$-s",
        else => "-L%1$-s",
    };
}
