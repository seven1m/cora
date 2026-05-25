const std = @import("std");
const prism = @import("prism.zig");
pub const Value = @import("value.zig").Value;
const build_options = @import("build_options");
const compiler = @import("compiler.zig");
const vm = @import("vm.zig");
const bdwgc = @import("bdwgc");

/// Implements Ruby's -x flag: scans forward through `code` and returns the
/// slice starting at the first line whose content begins with "#!" and contains
/// "ruby" or "cora".  If no such line is found the original slice is returned
/// unchanged so the script fails naturally (same behaviour as MRI).
fn stripLeadingGarbage(code: []const u8) []const u8 {
    var offset: usize = 0;
    while (offset < code.len) {
        const nl = std.mem.indexOfScalarPos(u8, code, offset, '\n');
        const line_end = nl orelse code.len;
        const line = std.mem.trimEnd(u8, code[offset..line_end], &[_]u8{'\r'});
        if (std.mem.startsWith(u8, line, "#!") and
            (std.mem.indexOf(u8, line, "ruby") != null or
                std.mem.indexOf(u8, line, "cora") != null))
        {
            return code[offset..];
        }
        offset = (nl orelse break) + 1;
    }
    return code;
}

fn parseDashZeroSeparator(arg: []const u8, storage: *[1]u8) ![]const u8 {
    const suffix = arg[2..];
    const parsed = if (suffix.len == 0)
        @as(u8, 0)
    else blk: {
        const value = try std.fmt.parseUnsigned(u16, suffix, 8);
        if (value > 0xff) {
            return error.InvalidDashZeroValue;
        }
        break :blk @as(u8, @intCast(value));
    };
    storage[0] = parsed;
    return storage[0..1];
}

fn appendColonSeparatedPaths(allocator: std.mem.Allocator, paths: *std.ArrayList([]const u8), arg: []const u8) !void {
    var it = std.mem.splitScalar(u8, arg, ':');
    while (it.next()) |raw| {
        const path = std.mem.trim(u8, raw, " \t\r\n");
        if (path.len == 0) continue;
        try paths.append(allocator, path);
    }
}

fn appendLoadPathIfExists(virtual_machine: *vm.VM, io: std.Io, candidate: []const u8) !void {
    var path_buffer: [4096]u8 = undefined;
    const abs_len = if (std.fs.path.isAbsolute(candidate))
        std.Io.Dir.realPathFileAbsolute(io, candidate, &path_buffer) catch return
    else
        std.Io.Dir.cwd().realPathFile(io, candidate, &path_buffer) catch return;
    try virtual_machine.appendLoadPath(path_buffer[0..abs_len]);
}

fn appendScriptDirectory(virtual_machine: *vm.VM, io: std.Io, script_path: []const u8) !void {
    var path_buffer: [4096]u8 = undefined;
    const abs_len = if (std.fs.path.isAbsolute(script_path))
        std.Io.Dir.realPathFileAbsolute(io, script_path, &path_buffer) catch return
    else
        std.Io.Dir.cwd().realPathFile(io, script_path, &path_buffer) catch return;
    const abs_path = path_buffer[0..abs_len];
    const dir = std.fs.path.dirname(abs_path) orelse return;
    try virtual_machine.appendLoadPath(dir);
}

fn configureLoadPath(
    allocator: std.mem.Allocator,
    virtual_machine: *vm.VM,
    io: std.Io,
    argv0: []const u8,
    script_path: ?[]const u8,
    extra_load_paths: []const []const u8,
) !void {
    if (script_path) |path| {
        try appendScriptDirectory(virtual_machine, io, path);
    }

    var exe_path_buffer: [4096]u8 = undefined;
    const exe_abs_len = if (std.fs.path.isAbsolute(argv0))
        std.Io.Dir.realPathFileAbsolute(io, argv0, &exe_path_buffer) catch 0
    else
        std.Io.Dir.cwd().realPathFile(io, argv0, &exe_path_buffer) catch 0;
    if (exe_abs_len != 0) {
        const exe_abs = exe_path_buffer[0..exe_abs_len];
        try virtual_machine.setRubyExecutablePath(exe_abs);
        if (std.fs.path.dirname(exe_abs)) |exe_dir| {
            const repo_stdlib = try std.fs.path.join(allocator, &.{ exe_dir, "..", "..", "lib", "stdlib" });
            defer allocator.free(repo_stdlib);
            try appendLoadPathIfExists(virtual_machine, io, repo_stdlib);

            const repo_rubygems = try std.fs.path.join(allocator, &.{ exe_dir, "..", "..", "ext", "rubygems", "lib" });
            defer allocator.free(repo_rubygems);
            try appendLoadPathIfExists(virtual_machine, io, repo_rubygems);

            const repo_logger = try std.fs.path.join(allocator, &.{ exe_dir, "..", "..", "ext", "logger", "lib" });
            defer allocator.free(repo_logger);
            try appendLoadPathIfExists(virtual_machine, io, repo_logger);

            const repo_delegate = try std.fs.path.join(allocator, &.{ exe_dir, "..", "..", "ext", "delegate", "lib" });
            defer allocator.free(repo_delegate);
            try appendLoadPathIfExists(virtual_machine, io, repo_delegate);

            const repo_time = try std.fs.path.join(allocator, &.{ exe_dir, "..", "..", "ext", "time", "lib" });
            defer allocator.free(repo_time);
            try appendLoadPathIfExists(virtual_machine, io, repo_time);

            const repo_optparse = try std.fs.path.join(allocator, &.{ exe_dir, "..", "..", "ext", "optparse", "lib" });
            defer allocator.free(repo_optparse);
            try appendLoadPathIfExists(virtual_machine, io, repo_optparse);

            const repo_uri = try std.fs.path.join(allocator, &.{ exe_dir, "..", "..", "ext", "uri", "lib" });
            defer allocator.free(repo_uri);
            try appendLoadPathIfExists(virtual_machine, io, repo_uri);
        }
    } else {
        try virtual_machine.setRubyExecutablePath(argv0);
    }

    for (extra_load_paths) |path| {
        try appendLoadPathIfExists(virtual_machine, io, path);
    }

    try virtual_machine.syncLoadPathGlobals();
}

fn printHelp() void {
    std.debug.print(
        \\Usage: cora [options] (-e CODE | FILE) [args]
        \\
        \\Run Ruby code with the Cora interpreter.
        \\
        \\Input:
        \\  -e CODE                Evaluate CODE instead of reading a file
        \\  FILE                   Run Ruby source from FILE
        \\
        \\Inspection:
        \\  --ast                  Parse and print Prism AST, then exit
        \\  --dump-bytecode        Compile and print bytecode disassembly, then exit
        \\  --dump-jit-source      Print TinyCC JIT source for compiled methods
        \\
        \\Load path and requires:
        \\  -I PATH[:PATH...]      Add directories to $LOAD_PATH
        \\  -r LIBRARY             Require LIBRARY before running the script
        \\
        \\Runtime:
        \\  --disable-gems         Skip RubyGems setup
        \\  --backtrace-limit=N    Limit printed backtrace frames
        \\  -0[OCTAL]              Set input record separator ($/) from octal byte
        \\  -x                     Skip leading text before a Ruby shebang line
        \\
        \\Help:
        \\  -h, --help             Show this help and exit
        \\
        \\Notes:
        \\  - Script arguments after FILE are available to Ruby via ARGV
        \\  - `--dump-jit-source` requires a build with -Dtcc-jit=true
        \\
    , .{});
}

fn printInvalidOptionAndExit(argv0: []const u8, arg: []const u8) noreturn {
    const exe_name = std.fs.path.basename(argv0);
    std.debug.print("{s}: invalid option {s}  (-h will show valid options) (RuntimeError)\n", .{ exe_name, arg });
    std.process.exit(1);
}

fn requireLibraries(virtual_machine: *vm.VM, libraries: []const []const u8) !void {
    for (libraries) |library| {
        const require_arg = try virtual_machine.newString(library, false);
        var require_args = [_]Value{require_arg};
        _ = try virtual_machine.callMethodByName(virtual_machine.main_self, "require", require_args[0..], null);
    }
}

pub fn main(init: std.process.Init) !void {
    bdwgc.init();
    defer bdwgc.deinit();

    const allocator = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    vm.installDefaultSignalHandlers();

    var ruby_code: ?[]const u8 = null;
    var filename: ?[]const u8 = null;
    var print_ast = false;
    var dump_bytecode = false;
    var dump_jit_source = false;
    var disable_gems = false;
    var strip_leading_garbage = false;
    var backtrace_limit: ?usize = null;
    var input_record_separator: ?[]const u8 = null;
    var input_record_separator_storage: [1]u8 = undefined;
    var source_file: ?[]const u8 = null;
    var script_args: std.ArrayList([]const u8) = .empty;
    defer script_args.deinit(allocator);
    var extra_load_paths: std.ArrayList([]const u8) = .empty;
    defer extra_load_paths.deinit(allocator);
    var required_libraries: std.ArrayList([]const u8) = .empty;
    defer required_libraries.deinit(allocator);

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (filename != null) {
            try script_args.append(allocator, args[i]);
            continue;
        }

        if (std.mem.eql(u8, args[i], "-e")) {
            if (i + 1 < args.len) {
                ruby_code = args[i + 1];
                i += 1;
            } else {
                std.debug.print("Error: -e requires an argument\n", .{});
                return;
            }
        } else if (std.mem.eql(u8, args[i], "-r")) {
            if (i + 1 < args.len) {
                try required_libraries.append(allocator, args[i + 1]);
                i += 1;
            } else {
                std.debug.print("Error: -r requires an argument\n", .{});
                return;
            }
        } else if (std.mem.startsWith(u8, args[i], "-r")) {
            try required_libraries.append(allocator, args[i][2..]);
        } else if (std.mem.eql(u8, args[i], "-I")) {
            if (i + 1 < args.len) {
                try appendColonSeparatedPaths(allocator, &extra_load_paths, args[i + 1]);
                i += 1;
            } else {
                std.debug.print("Error: -I requires an argument\n", .{});
                return;
            }
        } else if (std.mem.startsWith(u8, args[i], "-I")) {
            try appendColonSeparatedPaths(allocator, &extra_load_paths, args[i][2..]);
        } else if (std.mem.startsWith(u8, args[i], "-0")) {
            input_record_separator = parseDashZeroSeparator(args[i], &input_record_separator_storage) catch {
                std.debug.print("Error: -0 requires an octal byte value between 000 and 377\n", .{});
                return;
            };
        } else if (std.mem.eql(u8, args[i], "-h") or std.mem.eql(u8, args[i], "--help")) {
            printHelp();
            return;
        } else if (std.mem.startsWith(u8, args[i], "--backtrace-limit=")) {
            backtrace_limit = std.fmt.parseUnsigned(usize, args[i]["--backtrace-limit=".len..], 10) catch {
                std.debug.print("Error: --backtrace-limit requires a non-negative integer\n", .{});
                return;
            };
        } else if (std.mem.eql(u8, args[i], "-x")) {
            strip_leading_garbage = true;
        } else if (std.mem.eql(u8, args[i], "--ast")) {
            print_ast = true;
        } else if (std.mem.eql(u8, args[i], "--dump-bytecode")) {
            dump_bytecode = true;
        } else if (std.mem.eql(u8, args[i], "--dump-jit-source")) {
            dump_jit_source = true;
        } else if (std.mem.eql(u8, args[i], "--disable-gems")) {
            disable_gems = true;
        } else if (!std.mem.startsWith(u8, args[i], "-")) {
            if (filename == null and ruby_code == null) {
                filename = args[i];
            } else {
                try script_args.append(allocator, args[i]);
            }
        } else {
            printInvalidOptionAndExit(args[0], args[i]);
        }
    }

    if (ruby_code == null and filename == null) {
        printHelp();
        return;
    }
    if (dump_jit_source and !build_options.tcc_jit) {
        std.debug.print("Error: --dump-jit-source requires building with -Dtcc-jit=true\n", .{});
        return;
    }

    var code_buffer: ?[]u8 = null;
    defer if (code_buffer) |buf| allocator.free(buf);

    const raw_code = if (ruby_code) |code|
        code
    else if (filename) |file| blk: {
        source_file = file;
        code_buffer = std.Io.Dir.cwd().readFileAlloc(init.io, file, allocator, .limited(std.math.maxInt(usize))) catch |err| {
            std.debug.print("Error: Could not read file '{s}': {}\n", .{ file, err });
            return;
        };

        break :blk code_buffer.?;
    } else unreachable;
    const code = if (strip_leading_garbage) stripLeadingGarbage(raw_code) else raw_code;
    var parser = prism.Parser.init(allocator, code, source_file) catch {
        std.debug.print("{s}: syntax error (SyntaxError)\n", .{source_file orelse "(eval)"});
        return;
    };
    defer parser.deinit();

    if (print_ast) {
        const output = try parser.prettyPrint(allocator);
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
        return;
    }

    var program = compiler.Compiler.compile(allocator, &parser, 1) catch |err| {
        if (compiler.syntaxErrorMessage(err)) |message| {
            std.debug.print("{s}: {s} (SyntaxError)\n", .{ source_file orelse "(eval)", message });
            return;
        }
        return err;
    };
    defer program.deinit();

    if (dump_bytecode) {
        // Print bytecode disassembly to stdout
        var stdout_buffer: [8192]u8 = undefined;
        var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
        const stdout = &stdout_writer.interface;

        // Print main chunk disassembly
        try program.main_chunk.disassemble(stdout);
        try stdout.print("\n", .{});

        // Print chunks
        var iter = program.child_chunks.iterator();
        while (iter.next()) |entry| {
            try entry.value_ptr.*.disassemble(stdout);
            try stdout.print("\n", .{});
        }

        try stdout.flush();

        return;
    }

    var virtual_machine = vm.VM.initEmpty(allocator, bdwgc.allocator, bdwgc.allocator_atomic, init.io, init.minimal.environ);
    try virtual_machine.prepare(&program);
    defer virtual_machine.deinit();
    try configureLoadPath(allocator, &virtual_machine, init.io, args[0], source_file, extra_load_paths.items);
    virtual_machine.setTccJitEnabled(build_options.tcc_jit);
    virtual_machine.setDisableGems(disable_gems);
    virtual_machine.setDumpJitSource(dump_jit_source);
    virtual_machine.setBacktraceLimit(backtrace_limit);
    try virtual_machine.setArgv(script_args.items);
    try virtual_machine.setProgramName(if (ruby_code != null) "-e" else source_file orelse args[0]);
    if (input_record_separator) |separator| {
        try virtual_machine.setInputRecordSeparator(separator, true);
    }
    try requireLibraries(&virtual_machine, required_libraries.items);

    const result = virtual_machine.run();

    const at_exit_result = virtual_machine.runAtExitHandlers();
    if (at_exit_result) |_| {
        // at_exit handlers completed
    } else |err| switch (err) {
        error.UnhandledException => {
            if (virtual_machine.unhandledExceptionExitStatus()) |status| {
                std.process.exit(status);
            }
            virtual_machine.printUnhandledException();
            std.process.exit(1);
        },
        else => return err,
    }

    if (result) |_| {
        // Success - program executed without unhandled exceptions
    } else |err| switch (err) {
        error.UnhandledException => {
            if (virtual_machine.unhandledExceptionExitStatus()) |status| {
                std.process.exit(status);
            }
            virtual_machine.printUnhandledException();
            std.process.exit(1);
        },
        else => return err, // Other errors propagate
    }
}
