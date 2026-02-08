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
    const options = b.addOptions();
    options.addOption(bool, "test_verbose", test_verbose);

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

    exe.linkLibC();

    const bdwgc = b.dependency("bdwgc_zig", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("bdwgc", bdwgc.module("bdwgc"));

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the VM");
    run_step.dependOn(&run_cmd.step);

    const test_filter = b.option([]const u8, "test-filter", "Filter tests by name");
    const test_filters = if (test_filter) |filter| &[_][]const u8{filter} else &.{};

    const test_exe = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/all_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = test_filters,
        .test_runner = .{ .path = b.path("src/test_runner.zig"), .mode = .simple },
    });

    test_exe.step.dependOn(prism_build_step);
    test_exe.step.dependOn(onigmo_build_step);
    test_exe.addObjectFile(b.path("zig-out/prism/build/libprism.a"));
    test_exe.addIncludePath(b.path("zig-out/prism/include"));
    test_exe.addObjectFile(b.path("zig-out/onigmo/.libs/libonigmo.a"));
    test_exe.addIncludePath(b.path("zig-out/onigmo/"));
    test_exe.linkLibC();

    test_exe.root_module.addImport("bdwgc", bdwgc.module("bdwgc"));
    test_exe.root_module.addImport("build_options", options.createModule());
    const cora_mod = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    cora_mod.addImport("bdwgc", bdwgc.module("bdwgc"));
    cora_mod.addIncludePath(b.path("zig-out/prism/include"));
    cora_mod.addIncludePath(b.path("zig-out/onigmo/"));
    cora_mod.addObjectFile(b.path("zig-out/onigmo/.libs/libonigmo.a"));
    test_exe.root_module.addImport("cora", cora_mod);

    const test_run = b.addRunArtifact(test_exe);
    test_run.step.dependOn(prism_build_step);
    test_run.step.dependOn(onigmo_build_step);
    test_run.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        test_run.addArgs(args);
    }

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
