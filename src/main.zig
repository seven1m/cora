const std = @import("std");
const prism = @import("prism.zig");
pub const Value = @import("value.zig").Value;
const compiler = @import("compiler.zig");
const vm = @import("vm.zig");
const bdwgc = @import("bdwgc");

pub fn main() !void {
    bdwgc.init();
    defer bdwgc.deinit();

    var gpa = if (std.debug.runtime_safety)
        std.heap.DebugAllocator(.{}){}
    else
        std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var ruby_code: ?[]const u8 = null;
    var filename: ?[]const u8 = null;
    var print_ast = false;
    var dump_bytecode = false;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-e")) {
            if (i + 1 < args.len) {
                ruby_code = args[i + 1];
                i += 1;
            } else {
                std.debug.print("Error: -e requires an argument\n", .{});
                return;
            }
        } else if (std.mem.eql(u8, args[i], "--ast")) {
            print_ast = true;
        } else if (std.mem.eql(u8, args[i], "--dump-bytecode")) {
            dump_bytecode = true;
        } else if (!std.mem.startsWith(u8, args[i], "-")) {
            filename = args[i];
        }
    }

    if (ruby_code == null and filename == null) {
        std.debug.print("Usage: clara [--ast] [--dump-bytecode] (-e <ruby code> | <filename>)\n", .{});
        return;
    }

    var code_buffer: ?[]u8 = null;
    defer if (code_buffer) |buf| allocator.free(buf);

    const code = if (ruby_code) |code|
        code
    else if (filename) |file| blk: {
        const file_handle = std.fs.cwd().openFile(file, .{}) catch |err| {
            std.debug.print("Error: Could not open file '{s}': {}\n", .{ file, err });
            return;
        };
        defer file_handle.close();

        const file_size = try file_handle.getEndPos();
        code_buffer = try allocator.alloc(u8, file_size);
        const bytes_read = try file_handle.readAll(code_buffer.?);

        if (bytes_read != file_size) {
            std.debug.print("Error: Could not read entire file\n", .{});
            return;
        }

        break :blk code_buffer.?;
    } else unreachable;
    var parser = prism.Parser.init(allocator, code) catch {
        std.debug.print("Parse error\n", .{});
        return;
    };

    if (print_ast) {
        defer parser.deinit();
        const output = try parser.prettyPrint(allocator);
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
        return;
    }

    var program = try compiler.Compiler.compile(allocator, bdwgc.allocator, &parser);
    defer program.deinit();

    if (dump_bytecode) {
        defer parser.deinit();
        // Print bytecode disassembly to stdout
        var stdout_buffer: [8192]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;

        // Print main chunk disassembly
        try program.main_chunk.disassemble(stdout);
        try stdout.print("\n", .{});

        // Print method chunks
        var iter = program.method_chunks.iterator();
        while (iter.next()) |entry| {
            try entry.value_ptr.*.disassemble(stdout);
            try stdout.print("\n", .{});
        }

        return;
    }

    var virtual_machine = vm.VM.init(allocator, bdwgc.allocator, parser, &program);
    defer virtual_machine.deinit();

    _ = try virtual_machine.run();
}
