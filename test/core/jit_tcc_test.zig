const std = @import("std");
const build_options = @import("build_options");
const cora = @import("cora");
const compiler = cora.compiler;
const jit = cora.jit;
const prism = cora.prism;
const Value = cora.value.Value;
const VM = cora.vm.VM;
const bdwgc = @import("bdwgc");

test "TinyCC JIT accepts fib-like chunk and executes it" {
    if (!build_options.tcc_jit) return error.SkipZigTest;

    const source =
        \\def fib(n)
        \\  if n == 0
        \\    0
        \\  elsif n == 1
        \\    1
        \\  else
        \\    fib(n - 1) + fib(n - 2)
        \\  end
        \\end
        \\
        \\fib(10)
    ;

    bdwgc.init();
    defer bdwgc.deinit();

    const allocator = std.testing.allocator;
    var parser = try prism.Parser.init(allocator, source, null);
    defer parser.deinit();

    var program = try compiler.Compiler.compile(allocator, &parser, 1);
    defer program.deinit();

    var fib_chunk = @as(?*cora.chunk.Chunk, null);
    var iter = program.child_chunks.iterator();
    while (iter.next()) |entry| {
        if (std.mem.eql(u8, entry.value_ptr.*.name, "fib")) {
            fib_chunk = entry.value_ptr.*;
            break;
        }
    }
    try std.testing.expect(fib_chunk != null);
    try jit.validateChunk(fib_chunk.?);

    var vm = VM.initEmpty(allocator, bdwgc.allocator, bdwgc.allocator_atomic);
    defer vm.deinit();
    try vm.prepare(&program);
    vm.setTccJitEnabled(true);

    const result = try vm.run();
    try std.testing.expectEqual(Value.integer(55).raw, result.raw);
}

test "TinyCC JIT rejects default-arg chunk" {
    if (!build_options.tcc_jit) return error.SkipZigTest;

    const source =
        \\def fib(n = 1)
        \\  n
        \\end
    ;

    const allocator = std.testing.allocator;
    var parser = try prism.Parser.init(allocator, source, null);
    defer parser.deinit();

    var program = try compiler.Compiler.compile(allocator, &parser, 1);
    defer program.deinit();

    var iter = program.child_chunks.iterator();
    while (iter.next()) |entry| {
        if (std.mem.eql(u8, entry.value_ptr.*.name, "fib")) {
            try std.testing.expectError(error.NotEligible, jit.validateChunk(entry.value_ptr.*));
            return;
        }
    }

    return error.TestUnexpectedResult;
}
