const std = @import("std");

const optimize_state_path = "zig-out/build-mode";

fn pathExists(b: *std.Build, sub_path: []const u8) bool {
    const io = b.graph.io;
    const cwd: std.Io.Dir = .cwd();

    cwd.access(io, sub_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => std.debug.panic("failed to access '{s}': {s}", .{ sub_path, @errorName(err) }),
    };

    return true;
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
    cwd.createDirPath(io, "zig-out") catch |err| {
        std.debug.panic("failed to create zig-out: {s}", .{@errorName(err)});
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

    const libonigmo_path = "zig-out/onigmo/.libs/libonigmo.a";

    const libonigmo_exists = pathExists(b, libonigmo_path);

    if (!libonigmo_exists) {
        const copy_step = b.addSystemCommand(&.{ "sh", "-c", "mkdir -p zig-out/onigmo && cp -r ext/onigmo/* zig-out/onigmo/" });
        onigmo_build_step.dependOn(&copy_step.step);

        const patch_step = b.addSystemCommand(&.{ "sh", "-c", "cd zig-out/onigmo && patch -p1 < ../../ext/onigmo.patch 2>/dev/null; true" });
        patch_step.step.dependOn(&copy_step.step);
        onigmo_build_step.dependOn(&patch_step.step);

        const autogen_step = b.addSystemCommand(&.{ "sh", "-c", "cd zig-out/onigmo && sh autogen.sh" });
        autogen_step.step.dependOn(&patch_step.step);
        onigmo_build_step.dependOn(&autogen_step.step);

        const configure_step = b.addSystemCommand(&.{ "sh", "-c", "cd zig-out/onigmo && ./configure --with-pic" });
        configure_step.step.dependOn(&autogen_step.step);
        onigmo_build_step.dependOn(&configure_step.step);

        const make_step = b.addSystemCommand(&.{ "sh", "-c", "cd zig-out/onigmo && make -j CFLAGS='-std=gnu17'" });
        make_step.step.dependOn(&configure_step.step);
        onigmo_build_step.dependOn(&make_step.step);
    }

    return onigmo_build_step;
}

fn buildPrism(b: *std.Build) *std.Build.Step {
    const prism_build_step = b.step("prism", "Build Prism library");

    const libprism_path = "zig-out/prism/build/libprism.a";

    const libprism_exists = pathExists(b, libprism_path);

    if (!libprism_exists) {
        const copy_step = b.addSystemCommand(&.{ "sh", "-c", "mkdir -p zig-out/prism && cp -r ext/prism/* zig-out/prism/" });
        prism_build_step.dependOn(&copy_step.step);

        const overlay_step = b.addSystemCommand(&.{ "sh", "-c", "cp -r ext/prism-templates/* zig-out/prism/" });
        overlay_step.step.dependOn(&copy_step.step);
        prism_build_step.dependOn(&overlay_step.step);

        const make_step = b.addSystemCommand(&.{ "make", "-C", "zig-out/prism", "static" });
        make_step.step.dependOn(&overlay_step.step);
        prism_build_step.dependOn(&make_step.step);
    }

    return prism_build_step;
}

fn buildTinyCC(b: *std.Build) *std.Build.Step {
    const tinycc_build_step = b.step("tinycc", "Build TinyCC library");

    const libtcc_path = "zig-out/tinycc/libtcc.a";

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

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = optimizeOptionDefaultReleaseFast(b);
    const test_verbose = b.option(bool, "test-verbose", "Print each test name") orelse false;
    const test_timing = b.option(bool, "test-timing", "Print elapsed time for each test") orelse false;
    const test_jobs = b.option(i32, "test-jobs", "Number of test worker processes (<=0 auto)") orelse 0;
    const test_timeout = b.option(u32, "test-timeout", "Per-test-file wall-clock timeout in seconds (0 = disabled)") orelse 0;
    const coverage = b.option(bool, "coverage", "Run tests under kcov and generate an HTML coverage report") orelse false;
    const coverage_output_dir = b.option([]const u8, "coverage-output-dir", "Directory for kcov output") orelse "zig-out/kcov";
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
    const onigmo_build_step = buildOnigmo(b);
    const tinycc_build_step = buildTinyCC(b);

    if (submodule_update_step) |s| {
        prism_build_step.dependOn(s);
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

    exe.root_module.addObjectFile(b.path("zig-out/prism/build/libprism.a"));
    exe.root_module.addIncludePath(b.path("zig-out/prism/include"));
    exe.root_module.addObjectFile(b.path("zig-out/onigmo/.libs/libonigmo.a"));
    exe.root_module.addIncludePath(b.path("zig-out/onigmo/"));
    exe.root_module.addCSourceFile(.{ .file = b.path("ext/dtoa.c") });
    if (tcc_jit) {
        exe.root_module.addObjectFile(b.path("zig-out/tinycc/libtcc.a"));
        exe.root_module.addIncludePath(b.path("zig-out/tinycc"));
        exe.root_module.addIncludePath(b.path("zig-out/tinycc"));
    }

    exe.root_module.link_libc = true;
    linkOpenSSL(exe.root_module);

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

    // Copy bin/gem (polyglot sh+ruby) alongside the cora binary.
    const install_gem = b.addInstallFile(b.path("bin/gem"), "bin/gem");
    install_gem.step.dependOn(&install_exe.step);
    const chmod_gem = b.addSystemCommand(&.{ "chmod", "+x", b.getInstallPath(.bin, "gem") });
    chmod_gem.step.dependOn(&install_gem.step);
    b.getInstallStep().dependOn(&chmod_gem.step);

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
    if (tcc_jit) {
        test_exe.step.dependOn(tinycc_build_step);
    }
    test_exe.root_module.addObjectFile(b.path("zig-out/prism/build/libprism.a"));
    test_exe.root_module.addIncludePath(b.path("zig-out/prism/include"));
    test_exe.root_module.addObjectFile(b.path("zig-out/onigmo/.libs/libonigmo.a"));
    test_exe.root_module.addIncludePath(b.path("zig-out/onigmo/"));
    test_exe.root_module.addCSourceFile(.{ .file = b.path("ext/dtoa.c") });
    if (tcc_jit) {
        test_exe.root_module.addObjectFile(b.path("zig-out/tinycc/libtcc.a"));
        test_exe.root_module.addIncludePath(b.path("zig-out/tinycc"));
        test_exe.root_module.addIncludePath(b.path("zig-out/tinycc"));
    }
    test_exe.root_module.link_libc = true;
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
    cora_mod.addIncludePath(b.path("zig-out/prism/include"));
    cora_mod.addIncludePath(b.path("zig-out/onigmo/"));
    cora_mod.addObjectFile(b.path("zig-out/onigmo/.libs/libonigmo.a"));
    linkOpenSSL(cora_mod);
    if (tcc_jit) {
        cora_mod.addIncludePath(b.path("zig-out/tinycc"));
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
                "--exclude-pattern=/nix/store,.zig-cache,zig-out/ext,zig-out/prism,zig-out/onigmo",
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
        "find . \\( -path ./zig-out -o -path ./ext \\) -prune -o \\( -name '*.zig' -o -name '*.rb' \\) -print | entr -c -s 'zig build test'",
    });
    const watch_step = b.step("watch", "Watch source files and rebuild/test on changes (requires entr)");
    watch_step.dependOn(&watch_cmd.step);
}
