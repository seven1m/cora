const std = @import("std");

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

    const prism_build_step = buildPrism(b);

    const exe = b.addExecutable(.{
        .name = "cora",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.step.dependOn(prism_build_step);

    exe.addObjectFile(b.path("zig-out/prism/build/libprism.a"));
    exe.addIncludePath(b.path("zig-out/prism/include"));

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

    const test_exe = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/all_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    test_exe.step.dependOn(prism_build_step);
    test_exe.addObjectFile(b.path("zig-out/prism/build/libprism.a"));
    test_exe.addIncludePath(b.path("zig-out/prism/include"));
    test_exe.linkLibC();

    test_exe.root_module.addImport("bdwgc", bdwgc.module("bdwgc"));

    const test_run = b.addRunArtifact(test_exe);
    test_run.step.dependOn(prism_build_step);
    test_run.step.dependOn(b.getInstallStep());

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&test_run.step);

    const watch_cmd = b.addSystemCommand(&.{
        "sh",
        "-c",
        "find . \\( -path ./zig-out -o -path ./ext \\) -prune -o \\( -name '*.zig' -o -name '*.rb' \\) -print | entr -c -s 'zig build test --summary all'",
    });
    const watch_step = b.step("watch", "Watch source files and rebuild/test on changes (requires entr)");
    watch_step.dependOn(&watch_cmd.step);
}
