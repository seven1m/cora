const std = @import("std");
const Translator = @import("translate_c").Translator;
const builtin = @import("builtin");
const rbconfig = @import("src/rbconfig/config.zig");
const default_gems = @import("src/default_gems.zig");
const native_extension_suffix = "." ++ rbconfig.nativeExtension();

const optimize_state_path = "zig-out/build-mode";
const build_work_dir = "zig-out";
const ruby_gem_api_version = "4.1.0";
const rubygems_build_root = "zig-out/rubygems";
const psych_build_root = "zig-out/psych";
const strscan_build_root = "zig-out/strscan";
const json_build_root = "zig-out/json";
const prism_build_root = "zig-out/prism";
const tinycc_build_root = "zig-out/tinycc";
const cext_build_root = "zig-out/cext";
const ffi_build_root = "zig-out/ffi";
const bundled_gems = [_]struct { name: []const u8, version: []const u8 }{
    .{ .name = "csv", .version = "3.3.6" },
    .{ .name = "power_assert", .version = "3.0.1" },
    .{ .name = "test-unit", .version = "3.7.5" },
};
const runtime_ext_dirs = [_][]const u8{
    "cgi",
    "delegate",
    "did_you_mean",
    "erb",
    "forwardable",
    "ipaddr",
    "logger",
    "open3",
    "optparse",
    "psych",
    "prism-templates",
    "rubygems",
    "shellwords",
    "singleton",
    "strscan",
    "tempfile",
    "time",
    "timeout",
    "tinycc",
    "tmpdir",
    "uri",
    "weakref",
    "yaml",
};

comptime {
    @setEvalBranchQuota(20000);
}

fn pathExists(b: *std.Build, sub_path: []const u8) bool {
    const io = b.graph.io;
    const cwd: std.Io.Dir = .cwd();

    cwd.access(io, sub_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => std.debug.panic("failed to access '{s}': {s}", .{ sub_path, @errorName(err) }),
    };

    return true;
}

fn addStepDependencies(step: *std.Build.Step, deps: []const *std.Build.Step) void {
    for (deps) |dep| {
        step.dependOn(dep);
    }
}

fn gemInstallRoot(b: *std.Build, name: []const u8, version: []const u8) []const u8 {
    return b.fmt("lib/gems/{s}/gems/{s}-{s}", .{ ruby_gem_api_version, name, version });
}

fn defaultGemLibInstallPath(b: *std.Build, name: []const u8, version: []const u8, basename: []const u8) []const u8 {
    return b.fmt("{s}/lib/{s}", .{ gemInstallRoot(b, name, version), basename });
}

fn addInstallGemDir(
    b: *std.Build,
    source_dir: std.Build.LazyPath,
    name: []const u8,
    version: []const u8,
    build_step: ?*std.Build.Step,
) *std.Build.Step {
    const install_step = b.addInstallDirectory(.{
        .source_dir = source_dir,
        .install_dir = .prefix,
        .install_subdir = gemInstallRoot(b, name, version),
    });
    if (build_step) |dep| {
        install_step.step.dependOn(dep);
    }
    b.getInstallStep().dependOn(&install_step.step);
    return &install_step.step;
}

const GemKind = enum { default, bundled };

fn addInstallDefaultGemNativeLib(
    b: *std.Build,
    source_file: std.Build.LazyPath,
    name: []const u8,
    version: []const u8,
    basename: []const u8,
    build_step: *std.Build.Step,
) *std.Build.Step {
    const install_step = b.addInstallFile(
        source_file,
        defaultGemLibInstallPath(b, name, version, basename),
    );
    install_step.step.dependOn(build_step);
    b.getInstallStep().dependOn(&install_step.step);
    return &install_step.step;
}

fn addWriteGemSpec(
    b: *std.Build,
    gemspec_dir: []const u8,
    name: []const u8,
    version: []const u8,
    kind: GemKind,
    install_steps: []const *std.Build.Step,
) *std.Build.Step {
    const spec_subdir = if (kind == .default) "specifications/default" else "specifications";
    const gemspec_path = b.fmt("zig-out/lib/gems/{s}/{s}/{s}-{s}.gemspec", .{
        ruby_gem_api_version, spec_subdir, name, version,
    });
    const script = b.fmt(
        "test -f '{s}' || zig-out/bin/cora -e '{s}'",
        .{
            gemspec_path,
            b.fmt(
                \\require "rubygems"
                \\require "fileutils"
                \\root = Dir.pwd
                \\spec_dir = File.join(root, "zig-out/lib/gems/{s}/{s}")
                \\FileUtils.mkdir_p(spec_dir)
                \\Dir.chdir("{s}") do
                \\  gemspec_name = File.basename(Dir.pwd) + ".gemspec"
                \\  spec = Gem::Specification.load(gemspec_name)
                \\  raise "unexpected gemspec" unless spec.name == "{s}" && spec.version.to_s == "{s}"
                \\  File.write(File.join(spec_dir, spec.full_name + ".gemspec"), spec.to_ruby)
                \\end
            ,
                .{ ruby_gem_api_version, spec_subdir, gemspec_dir, name, version },
            ),
        },
    );
    const cmd = b.addSystemCommand(&.{ "sh", "-c", script });
    addStepDependencies(&cmd.step, install_steps);
    b.getInstallStep().dependOn(&cmd.step);
    return &cmd.step;
}

fn optimizeModeName(mode: std.builtin.OptimizeMode) []const u8 {
    return switch (mode) {
        .debug => "debug",
        .safe => "safe",
        .fast => "fast",
        .small => "small",
    };
}

fn parseOptimizeMode(raw: []const u8) ?std.builtin.OptimizeMode {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (std.mem.eql(u8, trimmed, "Debug") or std.mem.eql(u8, trimmed, "debug")) return .debug;
    if (std.mem.eql(u8, trimmed, "ReleaseSafe") or std.mem.eql(u8, trimmed, "safe")) return .safe;
    if (std.mem.eql(u8, trimmed, "ReleaseFast") or std.mem.eql(u8, trimmed, "fast")) return .fast;
    if (std.mem.eql(u8, trimmed, "ReleaseSmall") or std.mem.eql(u8, trimmed, "small")) return .small;
    return null;
}

fn readSavedOptimizeMode(b: *std.Build) ?std.builtin.OptimizeMode {
    const io = b.graph.io;
    const cwd: std.Io.Dir = .cwd();
    const contents = cwd.readFileAlloc(io, optimize_state_path, b.allocator, .limited(64)) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => std.debug.panic("failed to read '{s}': {s}", .{ optimize_state_path, @errorName(err) }),
    };
    defer b.allocator.free(contents);

    return parseOptimizeMode(contents);
}

fn writeSavedOptimizeMode(b: *std.Build, mode: std.builtin.OptimizeMode) void {
    const io = b.graph.io;
    const cwd: std.Io.Dir = .cwd();
    cwd.createDirPath(io, build_work_dir) catch |err| {
        std.debug.panic("failed to create {s}: {s}", .{ build_work_dir, @errorName(err) });
    };
    cwd.writeFile(io, .{
        .sub_path = optimize_state_path,
        .data = optimizeModeName(mode),
    }) catch |err| {
        std.debug.panic("failed to write '{s}': {s}", .{ optimize_state_path, @errorName(err) });
    };
}

fn buildOnigmo(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
    });
    module.addIncludePath(b.path("ext/onigmo"));
    module.addIncludePath(b.path("ext/onigmo/compat"));
    module.addIncludePath(b.path("ext/onigmo/enc/unicode/17.0.0"));
    // Use Onigmo's memcpy-based reads; direct unaligned loads trip C safety checks.
    module.addCSourceFiles(.{ .root = b.path("ext/onigmo"), .files = &.{
        "enc/ascii.c",
        "enc/big5.c",
        "enc/euc_jp.c",
        "enc/euc_kr.c",
        "enc/euc_tw.c",
        "enc/gb18030.c",
        "enc/iso_8859_1.c",
        "enc/iso_8859_10.c",
        "enc/iso_8859_11.c",
        "enc/iso_8859_13.c",
        "enc/iso_8859_14.c",
        "enc/iso_8859_15.c",
        "enc/iso_8859_16.c",
        "enc/iso_8859_2.c",
        "enc/iso_8859_3.c",
        "enc/iso_8859_4.c",
        "enc/iso_8859_5.c",
        "enc/iso_8859_6.c",
        "enc/iso_8859_7.c",
        "enc/iso_8859_8.c",
        "enc/iso_8859_9.c",
        "enc/koi8_r.c",
        "enc/koi8_u.c",
        "enc/shift_jis.c",
        "enc/unicode.c",
        "enc/utf_16be.c",
        "enc/utf_16le.c",
        "enc/utf_32be.c",
        "enc/utf_32le.c",
        "enc/utf_8.c",
        "enc/windows_1250.c",
        "enc/windows_1251.c",
        "enc/windows_1252.c",
        "enc/windows_1253.c",
        "enc/windows_1254.c",
        "enc/windows_1257.c",
        "enc/windows_31j.c",
        "regcomp.c",
        "regenc.c",
        "regerror.c",
        "regexec.c",
        "regparse.c",
        "regsyntax.c",
        "st.c",
    }, .flags = &.{ "-std=gnu17", "-DNOT_RUBY", "-DUNALIGNED_WORD_ACCESS=0" } });
    const library = b.addLibrary(.{
        .name = "onigmo",
        .linkage = .static,
        .root_module = module,
    });
    b.step("onigmo", "Build MRI's vendored Onigmo library").dependOn(&library.step);
    return library;
}

fn buildPrism(b: *std.Build, submodule_update_step: ?*std.Build.Step) *std.Build.Step {
    const prism_build_step = b.step("prism", "Build Prism library");
    const source_step = b.addSystemCommand(&.{
        "sh", "-c",
        \\changed=false
        \\for source in ext/prism/src/*.c ext/prism/include/prism/*.h; do
        \\  cmp -s "$source" "zig-out/prism/${source#ext/prism/}" || changed=true
        \\done
        \\for source in ext/prism-templates/include/prism/*.h ext/prism-templates/src/*.c; do
        \\  cmp -s "$source" "zig-out/prism/${source#ext/prism-templates/}" || changed=true
        \\done
        \\if [ "$changed" = true ]; then
        \\  rm -rf zig-out/prism
        \\  mkdir -p zig-out/prism
        \\  cp -r ext/prism/* zig-out/prism/
        \\  cp -r ext/prism-templates/* zig-out/prism/
        \\fi
    });
    if (submodule_update_step) |step| source_step.step.dependOn(step);

    const make_step = b.addSystemCommand(&.{ "make", "-C", "zig-out/prism", "static", "shared", b.fmt("SOEXT={s}", .{rbconfig.sharedLibraryExtension()}) });
    make_step.step.dependOn(&source_step.step);
    prism_build_step.dependOn(&make_step.step);

    return prism_build_step;
}

fn buildTinyCC(b: *std.Build) *std.Build.Step {
    const tinycc_build_step = b.step("tinycc", "Build TinyCC library");

    const libtcc_path = tinycc_build_root ++ "/libtcc.a";

    const libtcc_exists = pathExists(b, libtcc_path);

    if (!libtcc_exists) {
        const copy_step = b.addSystemCommand(&.{ "sh", "-c", "mkdir -p zig-out/tinycc && cp -r ext/tinycc/* zig-out/tinycc/" });
        tinycc_build_step.dependOn(&copy_step.step);

        const configure_step = b.addSystemCommand(&.{ "sh", "-c", "cd zig-out/tinycc && ./configure --with-pic" });
        configure_step.step.dependOn(&copy_step.step);
        tinycc_build_step.dependOn(&configure_step.step);

        const make_step = b.addSystemCommand(&.{ "make", "-C", "zig-out/tinycc" });
        make_step.step.dependOn(&configure_step.step);
        tinycc_build_step.dependOn(&make_step.step);
    }

    return tinycc_build_step;
}

const PsychBuild = struct {
    step: *std.Build.Step,
    extconf_step: *std.Build.Step,
};

const StrscanBuild = struct {
    step: *std.Build.Step,
    extconf_step: *std.Build.Step,
};

const JsonBuild = struct {
    step: *std.Build.Step,
    parser_extconf_step: *std.Build.Step,
    generator_extconf_step: *std.Build.Step,
};

fn buildPsych(b: *std.Build) PsychBuild {
    const psych_build_step = b.step("psych", "Build Psych native extension");
    const psych_so_path = psych_build_root ++ "/ext/psych" ++ native_extension_suffix;

    if (!pathExists(b, psych_so_path)) {
        const mkdir_step = b.addSystemCommand(&.{ "mkdir", "-p", psych_build_root ++ "/ext" });
        psych_build_step.dependOn(&mkdir_step.step);

        const extconf_step = b.addSystemCommand(&.{
            "sh",
            "-c",
            "repo_root=\"$PWD\" && cd zig-out/psych/ext && \"$repo_root\"/zig-out/bin/cora \"$repo_root\"/ext/psych/ext/psych/extconf.rb",
        });
        extconf_step.step.dependOn(&mkdir_step.step);
        psych_build_step.dependOn(&extconf_step.step);

        const make_step = b.addSystemCommand(&.{ "make", "-C", psych_build_root ++ "/ext" });
        make_step.step.dependOn(&extconf_step.step);
        psych_build_step.dependOn(&make_step.step);

        return .{
            .step = psych_build_step,
            .extconf_step = &extconf_step.step,
        };
    }

    return .{
        .step = psych_build_step,
        .extconf_step = psych_build_step,
    };
}

fn buildStrscan(b: *std.Build) StrscanBuild {
    const strscan_build_step = b.step("strscan", "Build Strscan native extension");
    const strscan_so_path = strscan_build_root ++ "/ext/strscan/strscan" ++ native_extension_suffix;

    if (!pathExists(b, strscan_so_path)) {
        const copy_step = b.addSystemCommand(&.{ "sh", "-c", "mkdir -p zig-out/strscan && cp -r ext/strscan/. zig-out/strscan/" });
        strscan_build_step.dependOn(&copy_step.step);

        const patch_step = b.addSystemCommand(&.{ "sh", "-c", "cd zig-out/strscan && patch -p1 < ../../ext/strscan.patch" });
        patch_step.step.dependOn(&copy_step.step);
        strscan_build_step.dependOn(&patch_step.step);

        const extconf_step = b.addSystemCommand(&.{
            "sh",
            "-c",
            "repo_root=\"$PWD\" && cd zig-out/strscan/ext/strscan && \"$repo_root\"/zig-out/bin/cora extconf.rb",
        });
        extconf_step.step.dependOn(&patch_step.step);
        strscan_build_step.dependOn(&extconf_step.step);

        const make_step = b.addSystemCommand(&.{ "make", "-C", strscan_build_root ++ "/ext/strscan" });
        make_step.step.dependOn(&extconf_step.step);
        strscan_build_step.dependOn(&make_step.step);

        return .{
            .step = strscan_build_step,
            .extconf_step = &extconf_step.step,
        };
    }

    return .{
        .step = strscan_build_step,
        .extconf_step = strscan_build_step,
    };
}

fn buildJson(b: *std.Build) JsonBuild {
    const json_build_step = b.step("json", "Build JSON native extensions");
    const parser_so_path = json_build_root ++ "/ext/json/ext/parser/parser" ++ native_extension_suffix;
    const generator_so_path = json_build_root ++ "/ext/json/ext/generator/generator" ++ native_extension_suffix;

    if (!pathExists(b, parser_so_path) or !pathExists(b, generator_so_path)) {
        const copy_step = b.addSystemCommand(&.{ "sh", "-c", "mkdir -p zig-out/json && cp -r ext/json/. zig-out/json/" });
        json_build_step.dependOn(&copy_step.step);

        const parser_extconf_step = b.addSystemCommand(&.{
            "sh",
            "-c",
            "repo_root=\"$PWD\" && cd zig-out/json/ext/json/ext/parser && \"$repo_root\"/zig-out/bin/cora extconf.rb",
        });
        parser_extconf_step.step.dependOn(&copy_step.step);
        json_build_step.dependOn(&parser_extconf_step.step);

        const parser_make_step = b.addSystemCommand(&.{ "make", "-C", json_build_root ++ "/ext/json/ext/parser" });
        parser_make_step.step.dependOn(&parser_extconf_step.step);
        json_build_step.dependOn(&parser_make_step.step);

        const generator_extconf_step = b.addSystemCommand(&.{
            "sh",
            "-c",
            "repo_root=\"$PWD\" && cd zig-out/json/ext/json/ext/generator && \"$repo_root\"/zig-out/bin/cora extconf.rb",
        });
        generator_extconf_step.step.dependOn(&copy_step.step);
        json_build_step.dependOn(&generator_extconf_step.step);

        const generator_make_step = b.addSystemCommand(&.{ "make", "-C", json_build_root ++ "/ext/json/ext/generator" });
        generator_make_step.step.dependOn(&generator_extconf_step.step);
        json_build_step.dependOn(&generator_make_step.step);

        return .{
            .step = json_build_step,
            .parser_extconf_step = &parser_extconf_step.step,
            .generator_extconf_step = &generator_extconf_step.step,
        };
    }

    return .{
        .step = json_build_step,
        .parser_extconf_step = json_build_step,
        .generator_extconf_step = json_build_step,
    };
}

fn buildCExtFixture(b: *std.Build) *std.Build.Step {
    const fixture_build_step = b.step("cext-fixture", "Build C extension fixture for tests");

    const fixture_so_path = cext_build_root ++ "/fixture" ++ native_extension_suffix;

    const mkdir_step = b.addSystemCommand(&.{ "mkdir", "-p", cext_build_root });
    fixture_build_step.dependOn(&mkdir_step.step);

    const compile_step = b.addSystemCommand(&.{ "gcc", if (builtin.os.tag.isDarwin()) "-bundle" else "-shared", "-fPIC", "-I", "include/cora", "test/support/cext_fixture.c", "-o", fixture_so_path });
    if (builtin.os.tag.isDarwin()) compile_step.addArgs(&.{ "-undefined", "dynamic_lookup" });
    compile_step.step.dependOn(&mkdir_step.step);
    fixture_build_step.dependOn(&compile_step.step);

    return fixture_build_step;
}

fn buildFFI(b: *std.Build) *std.Build.Step {
    const ffi_build_step = b.step("ffi", "Build Cora FFI extension");

    const mkdir_step = b.addSystemCommand(&.{ "mkdir", "-p", ffi_build_root });
    ffi_build_step.dependOn(&mkdir_step.step);

    const dynamic_lookup = if (builtin.os.tag.isDarwin()) " -undefined dynamic_lookup" else "";
    const compile_step = b.addSystemCommand(&.{ "sh", "-c", (if (builtin.os.tag.isDarwin()) "gcc -bundle" else "gcc -shared") ++ " -fPIC -I include/cora $(pkg-config --cflags libffi) ext/cora_ffi.c -o zig-out/ffi/cora_ffi" ++ native_extension_suffix ++ " $(pkg-config --libs libffi) -ldl" ++ dynamic_lookup });
    compile_step.step.dependOn(&mkdir_step.step);
    ffi_build_step.dependOn(&compile_step.step);

    return ffi_build_step;
}

fn linkSystemLibraries(module: *std.Build.Module) void {
    module.linkSystemLibrary("ssl", .{});
    module.linkSystemLibrary("crypto", .{});
    module.linkSystemLibrary("z", .{});
}

fn optimizeOptionDefaultReleaseFast(b: *std.Build) std.builtin.OptimizeMode {
    if (b.option(std.builtin.OptimizeMode, "optimize", "Prioritize performance, safety, or binary size")) |mode| {
        writeSavedOptimizeMode(b, mode);
        return mode;
    }

    if (readSavedOptimizeMode(b)) |mode| {
        return mode;
    }

    return .fast;
}

fn buildSizeofRb(b: *std.Build) []const u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(b.allocator);

    out.appendSlice(b.allocator, "# frozen_string_literal: true\n") catch @panic("OOM building sizeof.rb");
    out.appendSlice(b.allocator, "# Generated at build time by zig build\n") catch @panic("OOM building sizeof.rb");
    out.appendSlice(b.allocator, "module RbConfig\n") catch @panic("OOM building sizeof.rb");
    out.appendSlice(b.allocator, "  SIZEOF = {\n") catch @panic("OOM building sizeof.rb");
    for (sizeof_entries) |entry| {
        appendRubyHashStringKey(&out, b, entry.key);
        out.print(b.allocator, " => {d},\n", .{entry.value}) catch @panic("OOM building sizeof.rb");
    }
    out.appendSlice(b.allocator, "  }.freeze\n") catch @panic("OOM building sizeof.rb");
    out.appendSlice(b.allocator, "  LIMITS = {\n") catch @panic("OOM building sizeof.rb");
    for (limits_entries) |entry| {
        appendRubyHashStringKey(&out, b, entry.key);
        out.print(b.allocator, " => {s},\n", .{entry.value_str}) catch @panic("OOM building sizeof.rb");
    }
    out.appendSlice(b.allocator, "  }.freeze\n") catch @panic("OOM building sizeof.rb");
    out.appendSlice(b.allocator, "end\n") catch @panic("OOM building sizeof.rb");

    return b.dupe(out.items);
}

const sizeof_entry = struct { key: []const u8, value: usize };

const sizeof_entries = [_]sizeof_entry{
    .{ .key = "int", .value = @sizeOf(c_int) },
    .{ .key = "short", .value = @sizeOf(c_short) },
    .{ .key = "long", .value = @sizeOf(c_long) },
    .{ .key = "long long", .value = @sizeOf(c_longlong) },
    .{ .key = "void*", .value = @sizeOf(*anyopaque) },
    .{ .key = "float", .value = @sizeOf(f32) },
    .{ .key = "double", .value = @sizeOf(f64) },
    .{ .key = "size_t", .value = @sizeOf(usize) },
    .{ .key = "ptrdiff_t", .value = @sizeOf(isize) },
    .{ .key = "int8_t", .value = @sizeOf(i8) },
    .{ .key = "uint8_t", .value = @sizeOf(u8) },
    .{ .key = "int16_t", .value = @sizeOf(i16) },
    .{ .key = "uint16_t", .value = @sizeOf(u16) },
    .{ .key = "int32_t", .value = @sizeOf(i32) },
    .{ .key = "uint32_t", .value = @sizeOf(u32) },
    .{ .key = "int64_t", .value = @sizeOf(i64) },
    .{ .key = "uint64_t", .value = @sizeOf(u64) },
    .{ .key = "intptr_t", .value = @sizeOf(isize) },
    .{ .key = "uintptr_t", .value = @sizeOf(usize) },
    .{ .key = "ssize_t", .value = @sizeOf(isize) },
};

const limits_entry = struct { key: []const u8, value_str: []const u8 };

const fixnum_max = @divTrunc(std.math.maxInt(i64), 2);
const fixnum_min = @divTrunc(std.math.minInt(i64), 2);

const limits_entries = [_]limits_entry{
    .{ .key = "FIXNUM_MAX", .value_str = comptimeStr(fixnum_max) },
    .{ .key = "FIXNUM_MIN", .value_str = comptimeStr(fixnum_min) },
    .{ .key = "CHAR_BIT", .value_str = comptimeStr(@as(i64, @sizeOf(u8) * 8)) },
    .{ .key = "INT_MAX", .value_str = comptimeStr(std.math.maxInt(c_int)) },
    .{ .key = "INT_MIN", .value_str = comptimeStr(std.math.minInt(c_int)) },
    .{ .key = "UINT_MAX", .value_str = comptimeStr(std.math.maxInt(c_uint)) },
    .{ .key = "LONG_MAX", .value_str = comptimeStr(std.math.maxInt(c_long)) },
    .{ .key = "LONG_MIN", .value_str = comptimeStr(std.math.minInt(c_long)) },
    .{ .key = "ULONG_MAX", .value_str = comptimeStr(std.math.maxInt(c_ulong)) },
    .{ .key = "SHORT_MAX", .value_str = comptimeStr(std.math.maxInt(c_short)) },
    .{ .key = "SHORT_MIN", .value_str = comptimeStr(std.math.minInt(c_short)) },
    .{ .key = "USHORT_MAX", .value_str = comptimeStr(std.math.maxInt(c_ushort)) },
    .{ .key = "LLONG_MAX", .value_str = comptimeStr(std.math.maxInt(c_longlong)) },
    .{ .key = "LLONG_MIN", .value_str = comptimeStr(std.math.minInt(c_longlong)) },
    .{ .key = "ULLONG_MAX", .value_str = comptimeStr(std.math.maxInt(c_ulonglong)) },
    .{ .key = "SIZE_MAX", .value_str = comptimeStr(std.math.maxInt(usize)) },
    .{ .key = "PTRDIFF_MAX", .value_str = comptimeStr(std.math.maxInt(isize)) },
    .{ .key = "PTRDIFF_MIN", .value_str = comptimeStr(std.math.minInt(isize)) },
    .{ .key = "INT8_MAX", .value_str = comptimeStr(std.math.maxInt(i8)) },
    .{ .key = "INT8_MIN", .value_str = comptimeStr(std.math.minInt(i8)) },
    .{ .key = "UINT8_MAX", .value_str = comptimeStr(std.math.maxInt(u8)) },
    .{ .key = "INT16_MAX", .value_str = comptimeStr(std.math.maxInt(i16)) },
    .{ .key = "INT16_MIN", .value_str = comptimeStr(std.math.minInt(i16)) },
    .{ .key = "UINT16_MAX", .value_str = comptimeStr(std.math.maxInt(u16)) },
    .{ .key = "INT32_MAX", .value_str = comptimeStr(std.math.maxInt(i32)) },
    .{ .key = "INT32_MIN", .value_str = comptimeStr(std.math.minInt(i32)) },
    .{ .key = "UINT32_MAX", .value_str = comptimeStr(std.math.maxInt(u32)) },
    .{ .key = "INT64_MAX", .value_str = comptimeStr(std.math.maxInt(i64)) },
    .{ .key = "INT64_MIN", .value_str = comptimeStr(std.math.minInt(i64)) },
    .{ .key = "UINT64_MAX", .value_str = comptimeStr(std.math.maxInt(u64)) },
    .{ .key = "INTPTR_MAX", .value_str = comptimeStr(std.math.maxInt(isize)) },
    .{ .key = "INTPTR_MIN", .value_str = comptimeStr(std.math.minInt(isize)) },
    .{ .key = "UINTPTR_MAX", .value_str = comptimeStr(std.math.maxInt(usize)) },
};

fn comptimeStr(val: anytype) []const u8 {
    @setEvalBranchQuota(20000);
    return std.fmt.comptimePrint("{}", .{val});
}

fn appendRubyHashStringKey(out: *std.ArrayList(u8), b: *std.Build, key: []const u8) void {
    out.appendSlice(b.allocator, "    \"") catch @panic("OOM building sizeof.rb");
    for (key) |c| {
        switch (c) {
            '\\' => out.appendSlice(b.allocator, "\\\\") catch @panic("OOM building sizeof.rb"),
            '"' => out.appendSlice(b.allocator, "\\\"") catch @panic("OOM building sizeof.rb"),
            else => out.append(b.allocator, c) catch @panic("OOM building sizeof.rb"),
        }
    }
    out.appendSlice(b.allocator, "\"") catch @panic("OOM building sizeof.rb");
}

fn buildCBindings(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, prism_step: *std.Build.Step, tinycc_step: *std.Build.Step) []const std.Build.Module.Import {
    const dep = b.dependency("translate_c", .{});
    const headers = b.addWriteFiles();
    const bindings = [_]struct { name: []const u8, header: []const u8, libs: []const Translator.LinkSystemLib = &.{} }{
        .{ .name = "prism_c", .header = "#include <prism.h>\n" },
        .{ .name = "onigmo_c", .header = "#include <onigmo.h>\n" },
        .{ .name = "tcc_c", .header = "#define _GNU_SOURCE 1\n#include <libtcc.h>\n#ifdef __linux__\n#include <dlfcn.h>\n#include <stdlib.h>\n#endif\n" },
        .{ .name = "openssl_c", .header = "#include <openssl/err.h>\n#include <openssl/evp.h>\n#include <openssl/pem.h>\n#include <openssl/rand.h>\n#include <openssl/ssl.h>\n#include <openssl/x509_vfy.h>\n", .libs = &.{ .{ .name = "ssl" }, .{ .name = "crypto" } } },
        .{ .name = "zlib_c", .header = "#include <zlib.h>\n", .libs = &.{.{ .name = "z" }} },
        .{ .name = "locale_c", .header = "#define _GNU_SOURCE 1\n#include <locale.h>\n#include <langinfo.h>\n#ifdef __APPLE__\n#include <xlocale.h>\n#endif\n" },
        .{ .name = "stat_c", .header = "#include <sys/stat.h>\n" },
    };
    const imports = b.allocator.alloc(std.Build.Module.Import, bindings.len) catch @panic("OOM");
    for (bindings, imports) |binding, *import| {
        const t: Translator = .init(dep, .{
            .name = binding.name,
            .c_source_file = headers.add(b.fmt("{s}.h", .{binding.name}), binding.header),
            .target = target,
            .optimize = optimize,
            .link_system_libs = binding.libs,
        });
        if (std.mem.eql(u8, binding.name, "prism_c")) {
            t.addIncludePath(b.path(prism_build_root ++ "/include"));
            t.run.step.dependOn(prism_step);
        } else if (std.mem.eql(u8, binding.name, "onigmo_c")) {
            t.addIncludePath(b.path("ext/onigmo"));
        } else if (std.mem.eql(u8, binding.name, "tcc_c")) {
            t.addIncludePath(b.path(tinycc_build_root));
            t.run.step.dependOn(tinycc_step);
        }
        import.* = .{ .name = binding.name, .module = t.mod };
    }
    return imports;
}

pub fn build(b: *std.Build) void {
    // Configuration reads generated files and persists the selected build mode.
    b.graph.poisonCache();
    const target = b.standardTargetOptions(.{});
    const optimize = optimizeOptionDefaultReleaseFast(b);
    const test_verbose = b.option(bool, "test-verbose", "Print each test name") orelse false;
    const test_timing = b.option(bool, "test-timing", "Print elapsed time for each test") orelse false;
    const test_trace = b.option(bool, "test-trace", "Print aggregate Ruby spec phase timings") orelse false;
    const test_jobs = b.option(i32, "test-jobs", "Number of test worker processes (<=0 auto)") orelse 0;
    const test_timeout = b.option(u32, "test-timeout", "Per-test-file wall-clock timeout in seconds (0 = disabled)") orelse 0;
    const coverage = b.option(bool, "coverage", "Run tests under kcov and generate an HTML coverage report") orelse false;
    const coverage_output_dir = b.option([]const u8, "coverage-output-dir", "Directory for kcov output") orelse "zig-out/kcov";
    const submodule_update = b.option(bool, "submodule-update", "Run `git submodule update --init` before building") orelse true;

    const submodule_update_step = if (submodule_update) blk: {
        const s = b.addSystemCommand(&.{ "git", "submodule", "update", "--init" });
        s.setName("git submodule update --init");
        break :blk &s.step;
    } else null;

    const options = b.addOptions();
    options.addOption(bool, "test_verbose", test_verbose);
    options.addOption(bool, "test_timing", test_timing);
    options.addOption(bool, "test_trace", test_trace);
    options.addOption(i32, "test_jobs", test_jobs);
    options.addOption(u32, "test_timeout", test_timeout);
    const build_options_mod = options.createModule();

    const prism_build_step = buildPrism(b, submodule_update_step);
    const psych_build = buildPsych(b);
    const psych_build_step = psych_build.step;
    const strscan_build = buildStrscan(b);
    const strscan_build_step = strscan_build.step;
    const json_build = buildJson(b);
    const json_build_step = json_build.step;
    const onigmo = buildOnigmo(b, target, optimize);
    const tinycc_build_step = buildTinyCC(b);
    const cext_fixture_step = buildCExtFixture(b);
    const ffi_build_step = buildFFI(b);
    const c_bindings = buildCBindings(b, target, optimize, prism_build_step, tinycc_build_step);

    if (submodule_update_step) |s| {
        prism_build_step.dependOn(s);
        psych_build_step.dependOn(s);
        strscan_build_step.dependOn(s);
        json_build_step.dependOn(s);
        tinycc_build_step.dependOn(s);
    }

    const exe = b.addExecutable(.{
        .name = "cora",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.step.dependOn(prism_build_step);
    exe.step.dependOn(tinycc_build_step);

    exe.root_module.addObjectFile(b.path(prism_build_root ++ "/build/libprism.a"));
    exe.root_module.addIncludePath(b.path(prism_build_root ++ "/include"));
    exe.root_module.linkLibrary(onigmo);
    exe.root_module.addIncludePath(b.path("ext/onigmo"));
    exe.root_module.addCSourceFile(.{ .file = b.path("ext/dtoa.c") });
    exe.root_module.addObjectFile(b.path(tinycc_build_root ++ "/libtcc.a"));
    exe.root_module.addIncludePath(b.path(tinycc_build_root));

    exe.root_module.link_libc = true;
    linkSystemLibraries(exe.root_module);

    exe.rdynamic = true;
    // Darwin otherwise strips C ABI exports referenced only by loaded bundles.
    if (target.result.os.tag.isDarwin()) exe.link_gc_sections = false;

    // On Darwin aarch64, getcontext() is deprecated and does not save
    // caller-saved registers (x0-x18), making GC root scanning unreliable.
    const bdwgc_cflags: []const u8 = if (target.result.os.tag.isDarwin() and target.result.cpu.arch.isAARCH64())
        "-DNO_GETCONTEXT"
    else
        "";
    const bdwgc = b.dependency("bdwgc_zig", .{
        .target = target,
        .optimize = optimize,
        .linkage = .static,
        .CFLAGS_EXTRA = bdwgc_cflags,
    });
    const zio = b.dependency("zio", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("bdwgc", bdwgc.module("bdwgc"));
    exe.root_module.addImport("build_options", build_options_mod);
    exe.root_module.addImport("zio", zio.module("zio"));
    for (c_bindings) |binding| exe.root_module.addImport(binding.name, binding.module);

    const install_exe = b.addInstallArtifact(exe, .{});
    b.getInstallStep().dependOn(&install_exe.step);

    const prepare_rubygems = b.addSystemCommand(&.{
        "sh",
        "-c",
        "rm -rf zig-out/rubygems && mkdir -p zig-out/rubygems && cp -r ext/rubygems/. zig-out/rubygems/ && cd zig-out/rubygems && patch -p1 < ../../ext/rubygems.patch",
    });

    for (runtime_ext_dirs) |dir_name| {
        const install_ext_dir = b.addInstallDirectory(.{
            .source_dir = b.path(if (std.mem.eql(u8, dir_name, "rubygems")) rubygems_build_root else b.fmt("ext/{s}", .{dir_name})),
            .install_dir = .prefix,
            .install_subdir = b.fmt("ext/{s}", .{dir_name}),
        });
        if (std.mem.eql(u8, dir_name, "rubygems")) {
            install_ext_dir.step.dependOn(&prepare_rubygems.step);
        }
        b.getInstallStep().dependOn(&install_ext_dir.step);
    }

    const install_stdlib = b.addInstallDirectory(.{
        .source_dir = b.path("lib/stdlib"),
        .install_dir = .prefix,
        .install_subdir = "lib/stdlib",
    });
    b.getInstallStep().dependOn(&install_stdlib.step);
    const prism_shared_name = if (builtin.os.tag.isDarwin()) "libprism.dylib" else "libprism.so";
    const install_prism_shared = b.addInstallFile(b.path(prism_build_root ++ "/build/" ++ prism_shared_name), "lib/prism/" ++ prism_shared_name);
    install_prism_shared.step.dependOn(prism_build_step);
    b.getInstallStep().dependOn(&install_prism_shared.step);
    const install_prism_headers = b.addInstallDirectory(.{
        .source_dir = b.path(prism_build_root ++ "/include"),
        .install_dir = .prefix,
        .install_subdir = "lib/prism/include",
    });
    install_prism_headers.step.dependOn(prism_build_step);
    b.getInstallStep().dependOn(&install_prism_headers.step);
    const install_ffi = b.addInstallFile(b.path(ffi_build_root ++ "/cora_ffi" ++ native_extension_suffix), "lib/stdlib/cora_ffi" ++ native_extension_suffix);
    install_ffi.step.dependOn(ffi_build_step);
    b.getInstallStep().dependOn(&install_ffi.step);
    const remove_legacy_json_stdlib = b.addSystemCommand(&.{ "rm", "-f" });
    remove_legacy_json_stdlib.addFileArg(.{ .relative = .{ .base = .install_prefix, .sub_path = "lib/stdlib/json.rb" } });
    remove_legacy_json_stdlib.step.dependOn(&install_stdlib.step);
    b.getInstallStep().dependOn(&remove_legacy_json_stdlib.step);
    const remove_legacy_json_ext_stdlib = b.addSystemCommand(&.{ "rm", "-f" });
    remove_legacy_json_ext_stdlib.addFileArg(.{ .relative = .{ .base = .install_prefix, .sub_path = "lib/stdlib/json/ext.rb" } });
    remove_legacy_json_ext_stdlib.step.dependOn(&install_stdlib.step);
    b.getInstallStep().dependOn(&remove_legacy_json_ext_stdlib.step);

    for (bundled_gems) |gem| {
        const install_gem = addInstallGemDir(b, b.path(b.fmt("ext/{s}", .{gem.name})), gem.name, gem.version, null);
        _ = addWriteGemSpec(b, b.fmt("ext/{s}", .{gem.name}), gem.name, gem.version, .bundled, &.{
            &install_exe.step,
            &install_stdlib.step,
            install_gem,
        });
    }

    const install_psych_default_gem_so = addInstallDefaultGemNativeLib(
        b,
        b.path(psych_build_root ++ "/ext/psych" ++ native_extension_suffix),
        "psych",
        default_gems.version("psych"),
        "psych" ++ native_extension_suffix,
        psych_build_step,
    );
    const install_strscan_default_gem_so = addInstallDefaultGemNativeLib(
        b,
        b.path(strscan_build_root ++ "/ext/strscan/strscan" ++ native_extension_suffix),
        "strscan",
        default_gems.version("strscan"),
        "strscan" ++ native_extension_suffix,
        strscan_build_step,
    );
    const install_json_default_gem_parser_so = addInstallDefaultGemNativeLib(
        b,
        b.path(json_build_root ++ "/ext/json/ext/parser/parser" ++ native_extension_suffix),
        "json",
        default_gems.version("json"),
        "json/ext/parser" ++ native_extension_suffix,
        json_build_step,
    );
    const install_json_default_gem_generator_so = addInstallDefaultGemNativeLib(
        b,
        b.path(json_build_root ++ "/ext/json/ext/generator/generator" ++ native_extension_suffix),
        "json",
        default_gems.version("json"),
        "json/ext/generator" ++ native_extension_suffix,
        json_build_step,
    );
    const install_headers = b.addInstallDirectory(.{
        .source_dir = b.path("include/cora"),
        .install_dir = .prefix,
        .install_subdir = "include/cora",
    });
    b.getInstallStep().dependOn(&install_headers.step);

    const install_oniguruma_header = b.addInstallFile(b.path("ext/onigmo/onigmo.h"), "include/cora/ruby/oniguruma.h");
    b.getInstallStep().dependOn(&install_oniguruma_header.step);

    // Generate zig-out/lib/stdlib/rbconfig/sizeof.rb at build time.
    const sizeof_rb_content = buildSizeofRb(b);
    const sizeof_rb_write = b.addWriteFiles();
    const sizeof_rb_file = sizeof_rb_write.add("rbconfig/sizeof.rb", sizeof_rb_content);
    const install_sizeof_rb = b.addInstallFile(sizeof_rb_file, "lib/stdlib/rbconfig/sizeof.rb");
    b.getInstallStep().dependOn(&install_sizeof_rb.step);

    // Copy bin/gem (polyglot sh+ruby) alongside the cora binary.
    const install_gem = b.addInstallFile(b.path("bin/gem"), "bin/gem");
    install_gem.step.dependOn(&install_exe.step);
    const chmod_gem = b.addSystemCommand(&.{ "chmod", "+x" });
    chmod_gem.addFileArg(.{ .relative = .{ .base = .install_prefix, .sub_path = "bin/gem" } });
    chmod_gem.step.dependOn(&install_gem.step);
    b.getInstallStep().dependOn(&chmod_gem.step);
    const native_gem_env_steps = [_]*std.Build.Step{
        &install_exe.step,
        &install_stdlib.step,
        &install_headers.step,
        &install_oniguruma_header.step,
        &install_sizeof_rb.step,
        &chmod_gem.step,
    };
    addStepDependencies(psych_build.extconf_step, &native_gem_env_steps);
    addStepDependencies(strscan_build.extconf_step, &native_gem_env_steps);
    addStepDependencies(json_build.parser_extconf_step, &native_gem_env_steps);
    addStepDependencies(json_build.generator_extconf_step, &native_gem_env_steps);

    const stdlib_gem_specs = b.addWriteFiles();
    for (default_gems.gems) |gem| {
        if (gem.source == .stdlib) {
            const source_path = b.fmt("lib/stdlib/{s}.rb", .{gem.name});
            const installed_path = defaultGemLibInstallPath(b, gem.name, gem.version, b.fmt("{s}.rb", .{gem.name}));
            const install_lib = b.addInstallFile(b.path(source_path), installed_path);
            b.getInstallStep().dependOn(&install_lib.step);

            const spec_name = b.fmt("{s}-{s}.gemspec", .{ gem.name, gem.version });
            const spec_file = stdlib_gem_specs.add(spec_name, b.fmt(
                "Gem::Specification.new do |s|\n  s.name = \"{s}\"\n  s.version = \"{s}\"\n  s.files = [\"lib/{s}.rb\"]\nend\n",
                .{ gem.name, gem.version, gem.name },
            ));
            const install_spec = b.addInstallFile(spec_file, b.fmt("lib/gems/{s}/specifications/default/{s}", .{ ruby_gem_api_version, spec_name }));
            b.getInstallStep().dependOn(&install_spec.step);
            continue;
        }

        const gem_dir = switch (gem.source) {
            .bundler => rubygems_build_root ++ "/bundler",
            .strscan => strscan_build_root,
            .json => json_build_root,
            .repository, .psych => b.fmt("ext/{s}", .{gem.name}),
            .stdlib => unreachable,
        };
        const build_step: ?*std.Build.Step = switch (gem.source) {
            .bundler => &prepare_rubygems.step,
            .strscan => strscan_build_step,
            .json => json_build_step,
            else => null,
        };
        const install_default_gem = addInstallGemDir(b, b.path(gem_dir), gem.name, gem.version, build_step);
        var deps: std.ArrayList(*std.Build.Step) = .empty;
        deps.appendSlice(b.allocator, &.{ &install_exe.step, &install_stdlib.step, install_default_gem }) catch @panic("out of memory");
        switch (gem.source) {
            .psych => deps.append(b.allocator, install_psych_default_gem_so) catch @panic("out of memory"),
            .strscan => deps.append(b.allocator, install_strscan_default_gem_so) catch @panic("out of memory"),
            .json => deps.appendSlice(b.allocator, &.{ install_json_default_gem_parser_so, install_json_default_gem_generator_so }) catch @panic("out of memory"),
            else => {},
        }
        _ = addWriteGemSpec(b, gem_dir, gem.name, gem.version, .default, deps.items);
    }
    const remove_legacy_csv_default_spec = b.addSystemCommand(&.{ "rm", "-f" });
    remove_legacy_csv_default_spec.addFileArg(.{ .relative = .{ .base = .install_prefix, .sub_path = "lib/gems/4.1.0/specifications/default/csv-3.3.6.gemspec" } });
    b.getInstallStep().dependOn(&remove_legacy_csv_default_spec.step);

    const install_cext_fixture = b.addInstallFile(b.path(cext_build_root ++ "/fixture" ++ native_extension_suffix), "cext/fixture" ++ native_extension_suffix);
    install_cext_fixture.step.dependOn(cext_fixture_step);
    b.getInstallStep().dependOn(&install_cext_fixture.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    run_cmd.addPassthruArgs();

    const run_step = b.step("run", "Run the VM");
    run_step.dependOn(&run_cmd.step);

    const test_filter = b.option([]const u8, "test-filter", "Filter tests by name (supports 'foo|bar' OR matching)");
    options.addOption([]const u8, "test_filter_raw", test_filter orelse "");
    var parsed_test_filters: std.ArrayList([]const u8) = .empty;
    if (test_filter) |filter| {
        var it = std.mem.splitScalar(u8, filter, '|');
        while (it.next()) |raw| {
            const part = std.mem.trim(u8, raw, " \t\r\n");
            if (part.len == 0) continue;
            parsed_test_filters.append(b.allocator, part) catch @panic("OOM parsing -Dtest-filter");
        }
    }
    const test_filters = parsed_test_filters.items;

    const test_exe = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/all_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = test_filters,
        .test_runner = .{ .path = b.path("src/test_runner.zig"), .mode = .simple },
        .use_llvm = if (coverage) true else null,
    });

    test_exe.step.dependOn(prism_build_step);
    test_exe.step.dependOn(cext_fixture_step);
    test_exe.step.dependOn(tinycc_build_step);
    test_exe.root_module.addObjectFile(b.path(prism_build_root ++ "/build/libprism.a"));
    test_exe.root_module.addIncludePath(b.path(prism_build_root ++ "/include"));
    test_exe.root_module.linkLibrary(onigmo);
    test_exe.root_module.addIncludePath(b.path("ext/onigmo"));
    test_exe.root_module.addCSourceFile(.{ .file = b.path("ext/dtoa.c") });
    test_exe.root_module.addObjectFile(b.path(tinycc_build_root ++ "/libtcc.a"));
    test_exe.root_module.addIncludePath(b.path(tinycc_build_root));
    test_exe.root_module.link_libc = true;
    test_exe.rdynamic = true;
    if (target.result.os.tag.isDarwin()) test_exe.link_gc_sections = false;
    linkSystemLibraries(test_exe.root_module);

    test_exe.root_module.addImport("bdwgc", bdwgc.module("bdwgc"));
    test_exe.root_module.addImport("build_options", build_options_mod);
    test_exe.root_module.addImport("zio", zio.module("zio"));
    for (c_bindings) |binding| test_exe.root_module.addImport(binding.name, binding.module);
    const cora_mod = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    cora_mod.addImport("bdwgc", bdwgc.module("bdwgc"));
    cora_mod.addImport("build_options", build_options_mod);
    cora_mod.addImport("zio", zio.module("zio"));
    for (c_bindings) |binding| cora_mod.addImport(binding.name, binding.module);
    cora_mod.addIncludePath(b.path(prism_build_root ++ "/include"));
    cora_mod.addIncludePath(b.path("ext/onigmo"));
    cora_mod.linkLibrary(onigmo);
    linkSystemLibraries(cora_mod);
    cora_mod.addIncludePath(b.path(tinycc_build_root));
    test_exe.root_module.addImport("cora", cora_mod);

    const ruby_spec_runner_mod = b.createModule(.{
        .root_source_file = b.path("test/ruby_spec_runner.zig"),
        .target = target,
        .optimize = optimize,
    });
    ruby_spec_runner_mod.addImport("cora", cora_mod);
    ruby_spec_runner_mod.addImport("bdwgc", bdwgc.module("bdwgc"));
    ruby_spec_runner_mod.addImport("build_options", build_options_mod);
    test_exe.root_module.addImport("ruby_spec_runner", ruby_spec_runner_mod);

    const test_run = blk: {
        if (coverage) {
            const include_pattern = b.fmt("{s}/", .{b.root.toString(b.allocator) catch @panic("OOM")});
            const run = b.addSystemCommand(&.{
                "kcov",
                "--clean",
                "--exclude-pattern=/nix/store,.zig-cache,zig-out/ext,zig-out/prism,zig-out/tinycc",
                b.fmt("--include-pattern={s}", .{include_pattern}),
                coverage_output_dir,
            });
            run.setName("kcov test");
            run.addArtifactArg(test_exe);
            run.addPassthruArgs();
            break :blk run;
        }

        break :blk b.addRunArtifact(test_exe);
    };
    const test_gem_home = b.root.joinString(b.allocator, "zig-out/lib/gems/" ++ ruby_gem_api_version) catch @panic("OOM");
    test_run.setEnvironmentVariable("GEM_HOME", test_gem_home);
    test_run.setEnvironmentVariable("GEM_PATH", test_gem_home);
    test_run.step.dependOn(prism_build_step);
    test_run.step.dependOn(&onigmo.step);
    test_run.step.dependOn(b.getInstallStep());

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&test_run.step);

    const watch_cmd = b.addSystemCommand(&.{
        "sh",
        "-c",
        "find . \\( -path ./zig-out -o -path ./ext \\) -prune -o \\( -name '*.zig' -o -name '*.rb' \\) -print | entr -c -s 'zig build test'",
    });
    const watch_step = b.step("watch", "Watch source files and rebuild/test on changes (requires entr)");
    watch_step.dependOn(&watch_cmd.step);
}
