const std = @import("std");
const test_helper = @import("test_helper.zig");

fn runSpec(path: []const u8) !void {
    var stdout_buf: [32768]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = test_helper.evalFile(path, &stdout_buf, &stderr_buf);

    if (result.err != null) {
        std.debug.print("\nSpec error ({s}): {s}\n{s}\n", .{ path, result.stdout, result.stderr });
        return error.SpecFailed;
    }

    if (std.mem.indexOf(u8, result.stdout, "OK:") == null) {
        std.debug.print("\nSpec failed ({s}):\n{s}\n", .{ path, result.stdout });
        return error.SpecFailed;
    }
}

fn collectSpecFiles(allocator: std.mem.Allocator, dir_path: []const u8, specs: *std.ArrayList([]const u8)) !void {
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
        std.debug.print("Failed to open directory {s}: {}\n", .{ dir_path, err });
        return;
    };
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, entry.name });

        if (entry.kind == .directory) {
            try collectSpecFiles(allocator, full_path, specs);
            allocator.free(full_path);
        } else if (entry.kind == .file) {
            if (std.mem.endsWith(u8, entry.name, "_spec.rb")) {
                try specs.append(allocator, full_path);
            } else {
                allocator.free(full_path);
            }
        } else {
            allocator.free(full_path);
        }
    }
}

test "ruby/spec" {
    const allocator = std.testing.allocator;
    var specs: std.ArrayList([]const u8) = .empty;
    defer {
        for (specs.items) |path| {
            allocator.free(path);
        }
        specs.deinit(allocator);
    }

    try collectSpecFiles(allocator, "spec", &specs);

    if (specs.items.len == 0) {
        std.debug.print("No spec files found in spec\n", .{});
        return error.NoSpecsFound;
    }

    var failed: usize = 0;
    var passed: usize = 0;

    for (specs.items) |spec_path| {
        runSpec(spec_path) catch {
            failed += 1;
            continue;
        };
        passed += 1;
    }

    if (failed > 0) {
        std.debug.print("\n{} specs passed, {} failed\n", .{ passed, failed });
        return error.SpecsFailed;
    }
}
