const std = @import("std");
const cora = @import("cora");
const compiler = cora.compiler;
const jit = cora.jit;
const prism = cora.prism;
const Value = cora.value.Value;
const VM = cora.vm.VM;
const bdwgc = @import("bdwgc");

test "TinyCC JIT accepts fib-like chunk and executes it" {
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

    var vm = VM.initEmpty(allocator, bdwgc.allocator, bdwgc.allocator_atomic, std.testing.io, std.testing.environ);
    defer vm.deinit();
    try vm.prepare(&program);
    vm.setTccJitEnabled(true);

    const result = try vm.run();
    try std.testing.expectEqual(Value.integer(55).raw, result.raw);
}

test "TinyCC JIT rejects default-arg chunk" {
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

test "TinyCC JIT generated source includes labels and helper calls" {
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
    ;

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

    const generated = try jit.generateChunk(allocator, fib_chunk.?);
    defer allocator.free(generated.symbol_name);
    defer allocator.free(generated.source_code);

    try std.testing.expect(std.mem.indexOf(u8, generated.source_code, "goto L") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated.source_code, "cora_jit_sub") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated.source_code, "cora_jit_add") != null);
}

fn findChunkByName(program: *const compiler.CompiledProgram, name: []const u8) ?*cora.chunk.Chunk {
    var iter = program.child_chunks.iterator();
    while (iter.next()) |entry| {
        if (std.mem.eql(u8, entry.value_ptr.*.name, name)) {
            return entry.value_ptr.*;
        }
    }
    return null;
}

fn taggedInt(n: i64) u64 {
    return @bitCast((n << 1) | 1);
}

test "TinyCC JIT accepts factorial chunk and executes it" {
    const source =
        \\def factorial(n)
        \\  if n == 0
        \\    1
        \\  else
        \\    n * factorial(n - 1)
        \\  end
        \\end
        \\
        \\factorial(6)
    ;

    bdwgc.init();
    defer bdwgc.deinit();

    const allocator = std.testing.allocator;
    var parser = try prism.Parser.init(allocator, source, null);
    defer parser.deinit();

    var program = try compiler.Compiler.compile(allocator, &parser, 1);
    defer program.deinit();

    const factorial_chunk = findChunkByName(&program, "factorial") orelse return error.TestUnexpectedResult;
    try jit.validateChunk(factorial_chunk);

    var vm = VM.initEmpty(allocator, bdwgc.allocator, bdwgc.allocator_atomic, std.testing.io, std.testing.environ);
    defer vm.deinit();
    try vm.prepare(&program);
    vm.setTccJitEnabled(true);

    const result = try vm.run();
    try std.testing.expectEqual(Value.integer(720).raw, result.raw);
}

test "TinyCC JIT accepts zero-argument chunk and executes it" {
    const source =
        \\def answer
        \\  42
        \\end
        \\
        \\answer
    ;

    bdwgc.init();
    defer bdwgc.deinit();

    const allocator = std.testing.allocator;
    var parser = try prism.Parser.init(allocator, source, null);
    defer parser.deinit();

    var program = try compiler.Compiler.compile(allocator, &parser, 1);
    defer program.deinit();

    const answer_chunk = findChunkByName(&program, "answer") orelse return error.TestUnexpectedResult;
    try jit.validateChunk(answer_chunk);

    var vm = VM.initEmpty(allocator, bdwgc.allocator, bdwgc.allocator_atomic, std.testing.io, std.testing.environ);
    defer vm.deinit();
    try vm.prepare(&program);
    vm.setTccJitEnabled(true);

    const result = try vm.run();
    try std.testing.expectEqual(Value.integer(42).raw, result.raw);
}

test "TinyCC JIT accepts two-argument recursive chunk and executes it" {
    const source =
        \\def countdown(a, b)
        \\  if a == 0
        \\    b
        \\  else
        \\    countdown(a - 1, b)
        \\  end
        \\end
        \\
        \\countdown(3, 42)
    ;

    bdwgc.init();
    defer bdwgc.deinit();

    const allocator = std.testing.allocator;
    var parser = try prism.Parser.init(allocator, source, null);
    defer parser.deinit();

    var program = try compiler.Compiler.compile(allocator, &parser, 1);
    defer program.deinit();

    const countdown_chunk = findChunkByName(&program, "countdown") orelse return error.TestUnexpectedResult;
    try jit.validateChunk(countdown_chunk);

    var vm = VM.initEmpty(allocator, bdwgc.allocator, bdwgc.allocator_atomic, std.testing.io, std.testing.environ);
    defer vm.deinit();
    try vm.prepare(&program);
    vm.setTccJitEnabled(true);

    const result = try vm.run();
    try std.testing.expectEqual(Value.integer(42).raw, result.raw);
}

test "TinyCC JIT accepts local mutation in while loop" {
    const source =
        \\def sum_to(n)
        \\  total = 0
        \\  while n > 0
        \\    total = total + n
        \\    n = n - 1
        \\  end
        \\  total
        \\end
        \\
        \\sum_to(10)
    ;

    bdwgc.init();
    defer bdwgc.deinit();

    const allocator = std.testing.allocator;
    var parser = try prism.Parser.init(allocator, source, null);
    defer parser.deinit();

    var program = try compiler.Compiler.compile(allocator, &parser, 1);
    defer program.deinit();

    const sum_to_chunk = findChunkByName(&program, "sum_to") orelse return error.TestUnexpectedResult;
    try jit.validateChunk(sum_to_chunk);

    var vm = VM.initEmpty(allocator, bdwgc.allocator, bdwgc.allocator_atomic, std.testing.io, std.testing.environ);
    defer vm.deinit();
    try vm.prepare(&program);
    vm.setTccJitEnabled(true);

    const result = try vm.run();
    try std.testing.expectEqual(Value.integer(55).raw, result.raw);
}

test "TinyCC JIT accepts recursive div chunk with floor semantics" {
    const source =
        \\def digit_count(n)
        \\  if n / 10 == 0
        \\    1
        \\  else
        \\    1 + digit_count(n / 10)
        \\  end
        \\end
        \\
        \\digit_count(100)
    ;

    bdwgc.init();
    defer bdwgc.deinit();

    const allocator = std.testing.allocator;
    var parser = try prism.Parser.init(allocator, source, null);
    defer parser.deinit();

    var program = try compiler.Compiler.compile(allocator, &parser, 1);
    defer program.deinit();

    const digit_count_chunk = findChunkByName(&program, "digit_count") orelse return error.TestUnexpectedResult;
    try jit.validateChunk(digit_count_chunk);

    var vm = VM.initEmpty(allocator, bdwgc.allocator, bdwgc.allocator_atomic, std.testing.io, std.testing.environ);
    defer vm.deinit();
    try vm.prepare(&program);
    vm.setTccJitEnabled(true);

    const result = try vm.run();
    try std.testing.expectEqual(Value.integer(3).raw, result.raw);
}

test "TinyCC JIT cora_jit_div floors negative quotients" {
    // -7 / 2 must be -4 (floor), not -3 (truncation toward zero).
    var ok: u8 = 1;
    const result = jit.cora_jit_div(taggedInt(-7), taggedInt(2), &ok);
    try std.testing.expectEqual(@as(u8, 1), ok);
    try std.testing.expectEqual(@as(i64, -4), @as(i64, @bitCast(result)) >> 1);
}

test "TinyCC JIT cora_jit_div bails on divide by zero" {
    var ok: u8 = 1;
    _ = jit.cora_jit_div(taggedInt(10), taggedInt(0), &ok);
    try std.testing.expectEqual(@as(u8, 0), ok);
}

test "TinyCC JIT cora_jit_mul bails on i63 overflow" {
    // Tagged (2^62 - 1) * (2^62 - 1) is well beyond i63 range; must bail.
    var ok: u8 = 1;
    _ = jit.cora_jit_mul(
        taggedInt((1 << 62) - 1),
        taggedInt((1 << 62) - 1),
        &ok,
    );
    try std.testing.expectEqual(@as(u8, 0), ok);
}

test "TinyCC JIT accepts comparison-op chunk and executes it" {
    // Exercises all four comparison ops (LT/GE/GT/LE) plus OPT_EQ in one chunk.
    // For n=75: not <0, not >=100, >50 → 3.
    const source =
        \\def band(n)
        \\  if n < 0
        \\    1
        \\  elsif n >= 100
        \\    4
        \\  elsif n > 50
        \\    3
        \\  elsif n <= 10
        \\    2
        \\  else
        \\    0
        \\  end
        \\end
        \\
        \\band(75)
    ;

    bdwgc.init();
    defer bdwgc.deinit();

    const allocator = std.testing.allocator;
    var parser = try prism.Parser.init(allocator, source, null);
    defer parser.deinit();

    var program = try compiler.Compiler.compile(allocator, &parser, 1);
    defer program.deinit();

    const band_chunk = findChunkByName(&program, "band") orelse return error.TestUnexpectedResult;
    try jit.validateChunk(band_chunk);

    var vm = VM.initEmpty(allocator, bdwgc.allocator, bdwgc.allocator_atomic, std.testing.io, std.testing.environ);
    defer vm.deinit();
    try vm.prepare(&program);
    vm.setTccJitEnabled(true);

    const result = try vm.run();
    try std.testing.expectEqual(Value.integer(3).raw, result.raw);
}

test "TinyCC JIT generated source includes mul and div helper calls" {
    const source =
        \\def factorial(n)
        \\  if n == 0
        \\    1
        \\  else
        \\    n * factorial(n - 1)
        \\  end
        \\end
    ;

    const allocator = std.testing.allocator;
    var parser = try prism.Parser.init(allocator, source, null);
    defer parser.deinit();

    var program = try compiler.Compiler.compile(allocator, &parser, 1);
    defer program.deinit();

    const factorial_chunk = findChunkByName(&program, "factorial") orelse return error.TestUnexpectedResult;
    const generated = try jit.generateChunk(allocator, factorial_chunk);
    defer allocator.free(generated.symbol_name);
    defer allocator.free(generated.source_code);

    try std.testing.expect(std.mem.indexOf(u8, generated.source_code, "cora_jit_mul") != null);

    const div_source =
        \\def halve(n)
        \\  n / 2
        \\end
    ;
    var div_parser = try prism.Parser.init(allocator, div_source, null);
    defer div_parser.deinit();
    var div_program = try compiler.Compiler.compile(allocator, &div_parser, 1);
    defer div_program.deinit();
    const halve_chunk = findChunkByName(&div_program, "halve") orelse return error.TestUnexpectedResult;
    const div_generated = try jit.generateChunk(allocator, halve_chunk);
    defer allocator.free(div_generated.symbol_name);
    defer allocator.free(div_generated.source_code);

    try std.testing.expect(std.mem.indexOf(u8, div_generated.source_code, "cora_jit_div") != null);
}
