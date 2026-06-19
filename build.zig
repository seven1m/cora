const std = @import("std");

const optimize_state_path = "build/build-mode";
const runtime_prefix = "build";
const ruby_gem_api_version = "4.0.0";
const onigmo_build_root = "build/onigmo";
const psych_build_root = "build/psych";
const strscan_build_root = "build/strscan";
const json_build_root = "build/json";
const csv_build_root = "build/csv";
const prism_build_root = "build/prism";
const tinycc_build_root = "build/tinycc";
const cext_build_root = "build/cext";
const psych_gem_version = "5.4.0";
const strscan_gem_version = "3.1.9";
const json_gem_version = "2.19.9";
const csv_gem_version = "3.3.6";
const yaml_gem_version = "0.4.0";
const runtime_ext_dirs = [_][]const u8{
    "cgi",
    "csv",
    "delegate",
    "erb",
    "forwardable",
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

fn defaultGemInstallRoot(b: *std.Build, name: []const u8, version: []const u8) []const u8 {
    return b.fmt("lib/gems/{s}/gems/{s}-{s}", .{ ruby_gem_api_version, name, version });
}

fn defaultGemLibInstallPath(b: *std.Build, name: []const u8, version: []const u8, basename: []const u8) []const u8 {
    return b.fmt("{s}/lib/{s}", .{ defaultGemInstallRoot(b, name, version), basename });
}

fn addInstallDefaultGemDir(
    b: *std.Build,
    source_dir: std.Build.LazyPath,
    name: []const u8,
    version: []const u8,
    build_step: ?*std.Build.Step,
) *std.Build.Step {
    const install_step = b.addInstallDirectory(.{
        .source_dir = source_dir,
        .install_dir = .prefix,
        .install_subdir = defaultGemInstallRoot(b, name, version),
    });
    if (build_step) |dep| {
        install_step.step.dependOn(dep);
    }
    b.getInstallStep().dependOn(&install_step.step);
    return &install_step.step;
}

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

fn addWriteDefaultGemSpec(
    b: *std.Build,
    gemspec_dir: []const u8,
    install_steps: []const *std.Build.Step,
) *std.Build.Step {
    const cmd = b.addSystemCommand(&.{
        "build/bin/cora",
        "-e",
        b.fmt(
            \\require "rubygems"
            \\root = Dir.pwd
            \\spec_dir = File.join(root, "build/lib/gems/{s}/specifications/default")
            \\spec_parent_dir = File.join(root, "build/lib/gems/{s}/specifications")
            \\Dir.mkdir(spec_parent_dir) unless File.directory?(spec_parent_dir)
            \\Dir.mkdir(spec_dir) unless File.directory?(spec_dir)
            \\Dir.chdir("{s}") do
            \\  gemspec_name = File.basename(Dir.pwd) + ".gemspec"
            \\  spec = Gem::Specification.load(gemspec_name)
            \\  File.write(File.join(spec_dir, spec.full_name + ".gemspec"), spec.to_ruby)
            \\end
            ,
            .{ ruby_gem_api_version, ruby_gem_api_version, gemspec_dir },
        ),
    });
    addStepDependencies(&cmd.step, install_steps);
    b.getInstallStep().dependOn(&cmd.step);
    return &cmd.step;
}

fn optimizeModeName(mode: std.builtin.OptimizeMode) []const u8 {
    return switch (mode) {
        .Debug => "Debug",
        .ReleaseSafe => "ReleaseSafe",
        .ReleaseFast => "ReleaseFast",
        .ReleaseSmall => "ReleaseSmall",
    };
}

fn parseOptimizeMode(raw: []const u8) ?std.builtin.OptimizeMode {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (std.mem.eql(u8, trimmed, "Debug")) return .Debug;
    if (std.mem.eql(u8, trimmed, "ReleaseSafe")) return .ReleaseSafe;
    if (std.mem.eql(u8, trimmed, "ReleaseFast")) return .ReleaseFast;
    if (std.mem.eql(u8, trimmed, "ReleaseSmall")) return .ReleaseSmall;
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
    cwd.createDirPath(io, runtime_prefix) catch |err| {
        std.debug.panic("failed to create {s}: {s}", .{ runtime_prefix, @errorName(err) });
    };
    cwd.writeFile(io, .{
        .sub_path = optimize_state_path,
        .data = optimizeModeName(mode),
    }) catch |err| {
        std.debug.panic("failed to write '{s}': {s}", .{ optimize_state_path, @errorName(err) });
    };
}

fn buildOnigmo(b: *std.Build) *std.Build.Step {
    const onigmo_build_step = b.step("onigmo", "Build Onigmo library");

    const libonigmo_path = onigmo_build_root ++ "/.libs/libonigmo.a";

    const libonigmo_exists = pathExists(b, libonigmo_path);

    if (!libonigmo_exists) {
        const copy_step = b.addSystemCommand(&.{ "sh", "-c", "mkdir -p build/onigmo && cp -r ext/onigmo/* build/onigmo/" });
        onigmo_build_step.dependOn(&copy_step.step);

        const patch_step = b.addSystemCommand(&.{ "sh", "-c", "cd build/onigmo && patch -p1 < ../../ext/onigmo.patch 2>/dev/null; true" });
        patch_step.step.dependOn(&copy_step.step);
        onigmo_build_step.dependOn(&patch_step.step);

        const autogen_step = b.addSystemCommand(&.{ "sh", "-c", "cd build/onigmo && sh autogen.sh" });
        autogen_step.step.dependOn(&patch_step.step);
        onigmo_build_step.dependOn(&autogen_step.step);

        const configure_step = b.addSystemCommand(&.{ "sh", "-c", "cd build/onigmo && ./configure --with-pic" });
        configure_step.step.dependOn(&autogen_step.step);
        onigmo_build_step.dependOn(&configure_step.step);

        const make_step = b.addSystemCommand(&.{ "sh", "-c", "cd build/onigmo && make -j CFLAGS='-std=gnu17'" });
        make_step.step.dependOn(&configure_step.step);
        onigmo_build_step.dependOn(&make_step.step);
    }

    return onigmo_build_step;
}

fn buildPrism(b: *std.Build) *std.Build.Step {
    const prism_build_step = b.step("prism", "Build Prism library");

    const libprism_path = prism_build_root ++ "/build/libprism.a";

    const libprism_exists = pathExists(b, libprism_path);

    if (!libprism_exists) {
        const copy_step = b.addSystemCommand(&.{ "sh", "-c", "mkdir -p build/prism && cp -r ext/prism/* build/prism/" });
        prism_build_step.dependOn(&copy_step.step);

        const overlay_step = b.addSystemCommand(&.{ "sh", "-c", "cp -r ext/prism-templates/* build/prism/" });
        overlay_step.step.dependOn(&copy_step.step);
        prism_build_step.dependOn(&overlay_step.step);

        const make_step = b.addSystemCommand(&.{ "make", "-C", "build/prism", "static" });
        make_step.step.dependOn(&overlay_step.step);
        prism_build_step.dependOn(&make_step.step);
    }

    return prism_build_step;
}

fn buildTinyCC(b: *std.Build) *std.Build.Step {
    const tinycc_build_step = b.step("tinycc", "Build TinyCC library");

    const libtcc_path = tinycc_build_root ++ "/libtcc.a";

    const libtcc_exists = pathExists(b, libtcc_path);

    if (!libtcc_exists) {
        const copy_step = b.addSystemCommand(&.{ "sh", "-c", "mkdir -p build/tinycc && cp -r ext/tinycc/* build/tinycc/" });
        tinycc_build_step.dependOn(&copy_step.step);

        const configure_step = b.addSystemCommand(&.{ "sh", "-c", "cd build/tinycc && ./configure --with-pic" });
        configure_step.step.dependOn(&copy_step.step);
        tinycc_build_step.dependOn(&configure_step.step);

        const make_step = b.addSystemCommand(&.{ "make", "-C", "build/tinycc" });
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
    const psych_so_path = psych_build_root ++ "/ext/psych.so";

    if (!pathExists(b, psych_so_path)) {
        const mkdir_step = b.addSystemCommand(&.{ "mkdir", "-p", psych_build_root ++ "/ext" });
        psych_build_step.dependOn(&mkdir_step.step);

        const extconf_step = b.addSystemCommand(&.{
            "sh",
            "-c",
            "repo_root=\"$PWD\" && cd build/psych/ext && \"$repo_root\"/build/bin/cora \"$repo_root\"/ext/psych/ext/psych/extconf.rb",
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
    const strscan_so_path = strscan_build_root ++ "/ext/strscan/strscan.so";

    if (!pathExists(b, strscan_so_path)) {
        const copy_step = b.addSystemCommand(&.{ "sh", "-c", "mkdir -p build/strscan && cp -r ext/strscan/. build/strscan/" });
        strscan_build_step.dependOn(&copy_step.step);

        const patch_step = b.addSystemCommand(&.{ "sh", "-c", "cd build/strscan && patch -p1 < ../../ext/strscan.patch" });
        patch_step.step.dependOn(&copy_step.step);
        strscan_build_step.dependOn(&patch_step.step);

        const extconf_step = b.addSystemCommand(&.{
            "sh",
            "-c",
            "repo_root=\"$PWD\" && cd build/strscan/ext/strscan && \"$repo_root\"/build/bin/cora extconf.rb",
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
    const parser_so_path = json_build_root ++ "/ext/json/ext/parser/parser.so";
    const generator_so_path = json_build_root ++ "/ext/json/ext/generator/generator.so";

    if (!pathExists(b, parser_so_path) or !pathExists(b, generator_so_path)) {
        const copy_step = b.addSystemCommand(&.{ "sh", "-c", "mkdir -p build/json && cp -r ext/json/. build/json/" });
        json_build_step.dependOn(&copy_step.step);

        const parser_extconf_step = b.addSystemCommand(&.{
            "sh",
            "-c",
            "repo_root=\"$PWD\" && cd build/json/ext/json/ext/parser && \"$repo_root\"/build/bin/cora extconf.rb",
        });
        parser_extconf_step.step.dependOn(&copy_step.step);
        json_build_step.dependOn(&parser_extconf_step.step);

        const parser_make_step = b.addSystemCommand(&.{ "make", "-C", json_build_root ++ "/ext/json/ext/parser" });
        parser_make_step.step.dependOn(&parser_extconf_step.step);
        json_build_step.dependOn(&parser_make_step.step);

        const generator_extconf_step = b.addSystemCommand(&.{
            "sh",
            "-c",
            "repo_root=\"$PWD\" && cd build/json/ext/json/ext/generator && \"$repo_root\"/build/bin/cora extconf.rb",
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

    const fixture_so_path = cext_build_root ++ "/fixture.so";

    const mkdir_step = b.addSystemCommand(&.{ "mkdir", "-p", cext_build_root });
    fixture_build_step.dependOn(&mkdir_step.step);

    const compile_step = b.addSystemCommand(&.{ "gcc", "-shared", "-fPIC", "-I", "include/cora", "test/support/cext_fixture.c", "-o", fixture_so_path });
    compile_step.step.dependOn(&mkdir_step.step);
    fixture_build_step.dependOn(&compile_step.step);

    return fixture_build_step;
}

fn linkOpenSSL(module: *std.Build.Module) void {
    module.linkSystemLibrary("ssl", .{});
    module.linkSystemLibrary("crypto", .{});
}

fn optimizeOptionDefaultReleaseFast(b: *std.Build) std.builtin.OptimizeMode {
    if (b.option(std.builtin.OptimizeMode, "optimize", "Prioritize performance, safety, or binary size")) |mode| {
        writeSavedOptimizeMode(b, mode);
        return mode;
    }

    if (readSavedOptimizeMode(b)) |mode| {
        return mode;
    }

    return .ReleaseFast;
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

pub fn build(b: *std.Build) void {
    b.resolveInstallPrefix(runtime_prefix, .{});

    const target = b.standardTargetOptions(.{});
    const optimize = optimizeOptionDefaultReleaseFast(b);
    const test_verbose = b.option(bool, "test-verbose", "Print each test name") orelse false;
    const test_timing = b.option(bool, "test-timing", "Print elapsed time for each test") orelse false;
    const test_jobs = b.option(i32, "test-jobs", "Number of test worker processes (<=0 auto)") orelse 0;
    const test_timeout = b.option(u32, "test-timeout", "Per-test-file wall-clock timeout in seconds (0 = disabled)") orelse 0;
    const coverage = b.option(bool, "coverage", "Run tests under kcov and generate an HTML coverage report") orelse false;
    const coverage_output_dir = b.option([]const u8, "coverage-output-dir", "Directory for kcov output") orelse "build/kcov";
    const tcc_jit = b.option(bool, "tcc-jit", "Build TinyCC-backed proof-of-concept JIT support") orelse false;
    const submodule_update = b.option(bool, "submodule-update", "Run `git submodule update --init` before building") orelse true;

    const submodule_update_step = if (submodule_update) blk: {
        const s = b.addSystemCommand(&.{ "git", "submodule", "update", "--init" });
        s.setName("git submodule update --init");
        break :blk &s.step;
    } else null;

    const options = b.addOptions();
    options.addOption(bool, "test_verbose", test_verbose);
    options.addOption(bool, "test_timing", test_timing);
    options.addOption(i32, "test_jobs", test_jobs);
    options.addOption(u32, "test_timeout", test_timeout);
    options.addOption(bool, "tcc_jit", tcc_jit);
    const build_options_mod = options.createModule();

    const prism_build_step = buildPrism(b);
    const psych_build = buildPsych(b);
    const psych_build_step = psych_build.step;
    const strscan_build = buildStrscan(b);
    const strscan_build_step = strscan_build.step;
    const json_build = buildJson(b);
    const json_build_step = json_build.step;
    const onigmo_build_step = buildOnigmo(b);
    const tinycc_build_step = buildTinyCC(b);
    const cext_fixture_step = buildCExtFixture(b);

    if (submodule_update_step) |s| {
        prism_build_step.dependOn(s);
        psych_build_step.dependOn(s);
        strscan_build_step.dependOn(s);
        json_build_step.dependOn(s);
        onigmo_build_step.dependOn(s);
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
    exe.step.dependOn(onigmo_build_step);
    if (tcc_jit) {
        exe.step.dependOn(tinycc_build_step);
    }

    exe.root_module.addObjectFile(b.path(prism_build_root ++ "/build/libprism.a"));
    exe.root_module.addIncludePath(b.path(prism_build_root ++ "/include"));
    exe.root_module.addObjectFile(b.path(onigmo_build_root ++ "/.libs/libonigmo.a"));
    exe.root_module.addIncludePath(b.path(onigmo_build_root ++ "/"));
    exe.root_module.addCSourceFile(.{ .file = b.path("ext/dtoa.c") });
    if (tcc_jit) {
        exe.root_module.addObjectFile(b.path(tinycc_build_root ++ "/libtcc.a"));
        exe.root_module.addIncludePath(b.path(tinycc_build_root));
        exe.root_module.addIncludePath(b.path(tinycc_build_root));
    }

    exe.root_module.link_libc = true;
    linkOpenSSL(exe.root_module);

    exe.rdynamic = true;

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

    const install_exe = b.addInstallArtifact(exe, .{});
    b.getInstallStep().dependOn(&install_exe.step);

    for (runtime_ext_dirs) |dir_name| {
        const install_ext_dir = b.addInstallDirectory(.{
            .source_dir = b.path(b.fmt("ext/{s}", .{dir_name})),
            .install_dir = .prefix,
            .install_subdir = b.fmt("ext/{s}", .{dir_name}),
        });
        b.getInstallStep().dependOn(&install_ext_dir.step);
    }

    const install_stdlib = b.addInstallDirectory(.{
        .source_dir = b.path("lib/stdlib"),
        .install_dir = .prefix,
        .install_subdir = "lib/stdlib",
    });
    b.getInstallStep().dependOn(&install_stdlib.step);
    const remove_legacy_json_stdlib = b.addSystemCommand(&.{ "rm", "-f", b.getInstallPath(.prefix, "lib/stdlib/json.rb") });
    remove_legacy_json_stdlib.step.dependOn(&install_stdlib.step);
    b.getInstallStep().dependOn(&remove_legacy_json_stdlib.step);
    const remove_legacy_json_ext_stdlib = b.addSystemCommand(&.{ "rm", "-f", b.getInstallPath(.prefix, "lib/stdlib/json/ext.rb") });
    remove_legacy_json_ext_stdlib.step.dependOn(&install_stdlib.step);
    b.getInstallStep().dependOn(&remove_legacy_json_ext_stdlib.step);

    const install_psych_default_gem = addInstallDefaultGemDir(b, b.path("ext/psych"), "psych", psych_gem_version, null);
    const install_strscan_default_gem = addInstallDefaultGemDir(b, b.path(strscan_build_root), "strscan", strscan_gem_version, strscan_build_step);
    const install_json_default_gem = addInstallDefaultGemDir(b, b.path(json_build_root), "json", json_gem_version, json_build_step);
    const install_csv_default_gem = addInstallDefaultGemDir(b, b.path("ext/csv"), "csv", csv_gem_version, null);
    const install_yaml_default_gem = addInstallDefaultGemDir(b, b.path("ext/yaml"), "yaml", yaml_gem_version, null);

    const install_psych_default_gem_so = addInstallDefaultGemNativeLib(
        b,
        b.path(psych_build_root ++ "/ext/psych.so"),
        "psych",
        psych_gem_version,
        "psych.so",
        psych_build_step,
    );
    const install_strscan_default_gem_so = addInstallDefaultGemNativeLib(
        b,
        b.path(strscan_build_root ++ "/ext/strscan/strscan.so"),
        "strscan",
        strscan_gem_version,
        "strscan.so",
        strscan_build_step,
    );
    const install_json_default_gem_parser_so = addInstallDefaultGemNativeLib(
        b,
        b.path(json_build_root ++ "/ext/json/ext/parser/parser.so"),
        "json",
        json_gem_version,
        "json/ext/parser.so",
        json_build_step,
    );
    const install_json_default_gem_generator_so = addInstallDefaultGemNativeLib(
        b,
        b.path(json_build_root ++ "/ext/json/ext/generator/generator.so"),
        "json",
        json_gem_version,
        "json/ext/generator.so",
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

    // Generate build/lib/stdlib/rbconfig/sizeof.rb at build time.
    const sizeof_rb_content = buildSizeofRb(b);
    const sizeof_rb_write = b.addWriteFiles();
    const sizeof_rb_file = sizeof_rb_write.add("rbconfig/sizeof.rb", sizeof_rb_content);
    const install_sizeof_rb = b.addInstallFile(sizeof_rb_file, "lib/stdlib/rbconfig/sizeof.rb");
    b.getInstallStep().dependOn(&install_sizeof_rb.step);

    // Copy bin/gem (polyglot sh+ruby) alongside the cora binary.
    const install_gem = b.addInstallFile(b.path("bin/gem"), "bin/gem");
    install_gem.step.dependOn(&install_exe.step);
    const chmod_gem = b.addSystemCommand(&.{ "chmod", "+x", b.getInstallPath(.bin, "gem") });
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

    _ = addWriteDefaultGemSpec(b, "ext/psych", &.{
        &install_exe.step,
        &install_stdlib.step,
        install_psych_default_gem,
        install_psych_default_gem_so,
    });
    _ = addWriteDefaultGemSpec(b, "build/strscan", &.{
        &install_exe.step,
        &install_stdlib.step,
        install_strscan_default_gem,
        install_strscan_default_gem_so,
    });
    _ = addWriteDefaultGemSpec(b, "build/json", &.{
        &install_exe.step,
        &install_stdlib.step,
        install_json_default_gem,
        install_json_default_gem_parser_so,
        install_json_default_gem_generator_so,
    });
    _ = addWriteDefaultGemSpec(b, "ext/csv", &.{
        &install_exe.step,
        &install_stdlib.step,
        install_csv_default_gem,
    });
    _ = addWriteDefaultGemSpec(b, "ext/yaml", &.{
        &install_exe.step,
        &install_stdlib.step,
        install_yaml_default_gem,
    });

    const install_cext_fixture = b.addInstallFile(b.path(cext_build_root ++ "/fixture.so"), "cext/fixture.so");
    install_cext_fixture.step.dependOn(cext_fixture_step);
    b.getInstallStep().dependOn(&install_cext_fixture.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

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
    test_exe.step.dependOn(onigmo_build_step);
    test_exe.step.dependOn(cext_fixture_step);
    if (tcc_jit) {
        test_exe.step.dependOn(tinycc_build_step);
    }
    test_exe.root_module.addObjectFile(b.path(prism_build_root ++ "/build/libprism.a"));
    test_exe.root_module.addIncludePath(b.path(prism_build_root ++ "/include"));
    test_exe.root_module.addObjectFile(b.path(onigmo_build_root ++ "/.libs/libonigmo.a"));
    test_exe.root_module.addIncludePath(b.path(onigmo_build_root ++ "/"));
    test_exe.root_module.addCSourceFile(.{ .file = b.path("ext/dtoa.c") });
    if (tcc_jit) {
        test_exe.root_module.addObjectFile(b.path(tinycc_build_root ++ "/libtcc.a"));
        test_exe.root_module.addIncludePath(b.path(tinycc_build_root));
        test_exe.root_module.addIncludePath(b.path(tinycc_build_root));
    }
    test_exe.root_module.link_libc = true;
    test_exe.rdynamic = true;
    linkOpenSSL(test_exe.root_module);

    test_exe.root_module.addImport("bdwgc", bdwgc.module("bdwgc"));
    test_exe.root_module.addImport("build_options", build_options_mod);
    test_exe.root_module.addImport("zio", zio.module("zio"));
    const cora_mod = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    cora_mod.addImport("bdwgc", bdwgc.module("bdwgc"));
    cora_mod.addImport("build_options", build_options_mod);
    cora_mod.addImport("zio", zio.module("zio"));
    cora_mod.addIncludePath(b.path(prism_build_root ++ "/include"));
    cora_mod.addIncludePath(b.path(onigmo_build_root ++ "/"));
    cora_mod.addObjectFile(b.path(onigmo_build_root ++ "/.libs/libonigmo.a"));
    linkOpenSSL(cora_mod);
    if (tcc_jit) {
        cora_mod.addIncludePath(b.path(tinycc_build_root));
    }
    test_exe.root_module.addImport("cora", cora_mod);

    const ruby_spec_runner_mod = b.createModule(.{
        .root_source_file = b.path("test/ruby_spec_runner.zig"),
        .target = target,
        .optimize = optimize,
    });
    ruby_spec_runner_mod.addImport("cora", cora_mod);
    ruby_spec_runner_mod.addImport("bdwgc", bdwgc.module("bdwgc"));
    test_exe.root_module.addImport("ruby_spec_runner", ruby_spec_runner_mod);

    const test_run = blk: {
        if (coverage) {
            const include_pattern = b.fmt("{s}/", .{b.build_root.path orelse "."});
            const run = b.addSystemCommand(&.{
                "kcov",
                "--clean",
                "--exclude-pattern=/nix/store,.zig-cache,build/ext,build/prism,build/onigmo,build/tinycc",
                b.fmt("--include-pattern={s}", .{include_pattern}),
                coverage_output_dir,
            });
            run.setName("kcov test");
            run.addArtifactArg(test_exe);
            if (b.args) |args| {
                run.addArgs(args);
            }
            break :blk run;
        }

        break :blk b.addRunArtifact(test_exe);
    };
    test_run.step.dependOn(prism_build_step);
    test_run.step.dependOn(onigmo_build_step);
    test_run.step.dependOn(b.getInstallStep());

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&test_run.step);

    const watch_cmd = b.addSystemCommand(&.{
        "sh",
        "-c",
        "find . \\( -path ./build -o -path ./ext \\) -prune -o \\( -name '*.zig' -o -name '*.rb' \\) -print | entr -c -s 'zig build test'",
    });
    const watch_step = b.step("watch", "Watch source files and rebuild/test on changes (requires entr)");
    watch_step.dependOn(&watch_cmd.step);
}
