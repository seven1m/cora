const std = @import("std");

fn buildOnigmo(b: *std.Build) *std.Build.Step {
    const onigmo_build_step = b.step("onigmo", "Build Onigmo library");

    const libonigmo_path = "zig-out/onigmo/.libs/libonigmo.a";

    const libonigmo_exists = std.fs.cwd().statFile(libonigmo_path) != std.fs.File.OpenError.FileNotFound;

    if (!libonigmo_exists) {
        const copy_step = b.addSystemCommand(&.{ "sh", "-c", "mkdir -p zig-out/onigmo && cp -r ext/onigmo/* zig-out/onigmo/" });
        onigmo_build_step.dependOn(&copy_step.step);

        const patch_step = b.addSystemCommand(&.{ "sh", "-c", "cd zig-out/onigmo && git apply ../../ext/onigmo.patch 2>/dev/null; true" });
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

    const libprism_exists = std.fs.cwd().statFile(libprism_path) != std.fs.File.OpenError.FileNotFound;

    if (!libprism_exists) {
        const copy_step = b.addSystemCommand(&.{ "sh", "-c", "mkdir -p zig-out/prism && cp -r ext/prism/* zig-out/prism/" });
        prism_build_step.dependOn(&copy_step.step);

        const templates_step = b.addSystemCommand(&.{ "sh", "-c", "cd zig-out/prism && PRISM_FFI_BACKEND=true rake templates" });
        templates_step.step.dependOn(&copy_step.step);
        prism_build_step.dependOn(&templates_step.step);

        const make_step = b.addSystemCommand(&.{ "make", "-C", "zig-out/prism", "static" });
        make_step.step.dependOn(&templates_step.step);
        prism_build_step.dependOn(&make_step.step);
    }

    return prism_build_step;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const test_verbose = b.option(bool, "test-verbose", "Print each test name") orelse false;
    const test_jobs = b.option(i32, "test-jobs", "Number of test worker processes (<=0 auto)") orelse 0;
    const coverage = b.option(bool, "coverage", "Run tests under kcov and generate an HTML coverage report") orelse false;
    const coverage_output_dir = b.option([]const u8, "coverage-output-dir", "Directory for kcov output") orelse "zig-out/kcov";
    const options = b.addOptions();
    options.addOption(bool, "test_verbose", test_verbose);
    options.addOption(i32, "test_jobs", test_jobs);

    const prism_build_step = buildPrism(b);
    const onigmo_build_step = buildOnigmo(b);

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

    exe.addObjectFile(b.path("zig-out/prism/build/libprism.a"));
    exe.addIncludePath(b.path("zig-out/prism/include"));
    exe.addObjectFile(b.path("zig-out/onigmo/.libs/libonigmo.a"));
    exe.addIncludePath(b.path("zig-out/onigmo/"));
    exe.addCSourceFile(.{ .file = b.path("ext/dtoa.c") });

    exe.linkLibC();

    const bdwgc = b.dependency("bdwgc_zig", .{
        .target = target,
        .optimize = optimize,
        .linkage = .static,
    });
    const zio = b.dependency("zio", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("bdwgc", bdwgc.module("bdwgc"));
    exe.root_module.addImport("zio", zio.module("zio"));

    b.installArtifact(exe);

    const lite_exe = b.addExecutable(.{
        .name = "cora_lite",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/cora_lite.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    lite_exe.step.dependOn(prism_build_step);
    lite_exe.addObjectFile(b.path("zig-out/prism/build/libprism.a"));
    lite_exe.addIncludePath(b.path("zig-out/prism/include"));
    lite_exe.linkLibC();

    b.installArtifact(lite_exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the VM");
    run_step.dependOn(&run_cmd.step);

    const run_lite_cmd = b.addRunArtifact(lite_exe);
    run_lite_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_lite_cmd.addArgs(args);
    }
    const run_lite_step = b.step("run-lite", "Run cora_lite");
    run_lite_step.dependOn(&run_lite_cmd.step);

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
    test_exe.addObjectFile(b.path("zig-out/prism/build/libprism.a"));
    test_exe.addIncludePath(b.path("zig-out/prism/include"));
    test_exe.addObjectFile(b.path("zig-out/onigmo/.libs/libonigmo.a"));
    test_exe.addIncludePath(b.path("zig-out/onigmo/"));
    test_exe.addCSourceFile(.{ .file = b.path("ext/dtoa.c") });
    test_exe.linkLibC();

    test_exe.root_module.addImport("bdwgc", bdwgc.module("bdwgc"));
    test_exe.root_module.addImport("zio", zio.module("zio"));
    test_exe.root_module.addImport("build_options", options.createModule());
    const cora_mod = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    cora_mod.addImport("bdwgc", bdwgc.module("bdwgc"));
    cora_mod.addImport("zio", zio.module("zio"));
    cora_mod.addIncludePath(b.path("zig-out/prism/include"));
    cora_mod.addIncludePath(b.path("zig-out/onigmo/"));
    cora_mod.addObjectFile(b.path("zig-out/onigmo/.libs/libonigmo.a"));
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
