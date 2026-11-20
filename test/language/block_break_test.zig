const std = @import("std");
const cora = @import("cora");
const bdwgc = @import("bdwgc");
const test_helper = @import("../test_helper.zig");
const evalCode = test_helper.evalCode;

test "compiler records literal block call-site handlers" {
    const allocator = test_helper.getAllocator();
    var parser = try cora.prism.Parser.init(allocator,
        \\receiver.foo { 1 }
        \\receiver.foo(key: 1) { 2 }
    , null);
    defer parser.deinit();

    var program = try cora.compiler.Compiler.compile(allocator, &parser, 1);
    defer program.deinit();

    const handlers = program.main_chunk.block_call_handlers.items;
    try std.testing.expectEqual(@as(usize, 2), handlers.len);
    for (handlers) |handler| {
        try std.testing.expect(handler.block_chunk_id != 0);
        try std.testing.expect(handler.continuation_byte_offset > handler.call_byte_offset);
    }
    try std.testing.expectEqual(@as(usize, 9), handlers[0].continuation_byte_offset - handlers[0].call_byte_offset);
    try std.testing.expectEqual(@as(usize, 12), handlers[1].continuation_byte_offset - handlers[1].call_byte_offset);
}

test "compiler keeps call-site tables dense after VM preparation" {
    bdwgc.init();
    defer bdwgc.deinit();
    const allocator = std.testing.allocator;
    var parser = try cora.prism.Parser.init(allocator,
        \\def forward(...)
        \\  sink(...)
        \\  sink(1, ...)
        \\end
        \\receiver.foo { 1 }
        \\receiver.foo(key: 1) { 2 }
    , null);
    defer parser.deinit();
    var program = try cora.compiler.Compiler.compile(allocator, &parser, 1);
    defer program.deinit();
    var vm = cora.vm.VM.initEmpty(allocator, cora.gc_allocator.scanned, cora.gc_allocator.atomic, std.testing.io, std.testing.environ);
    defer vm.deinit();
    try vm.prepare(&program);

    // Each receiver expression and foo call gets one descriptor, independently
    // of byte offsets. Pointer caches are allocated only when the chunk runs.
    try std.testing.expectEqual(@as(usize, 0), program.main_chunk.callsite_caches.items.len);
    try std.testing.expectEqual(@as(usize, 4), program.main_chunk.callsite_descriptors.items.len);
    for (program.main_chunk.callsite_descriptors.items) |descriptor| try std.testing.expect(descriptor.initialized);

    var iter = program.child_chunks.valueIterator();
    while (iter.next()) |ptr| {
        if (!std.mem.eql(u8, ptr.*.name, "forward")) continue;
        // Forwarding sites reserve descriptors; cache slots stay lazy too.
        try std.testing.expectEqual(@as(usize, 0), ptr.*.callsite_caches.items.len);
        try std.testing.expectEqual(@as(usize, 2), ptr.*.callsite_descriptors.items.len);
        return;
    }
    return error.TestUnexpectedResult;
}

test "call-site dispatch payloads share lookup and invalidate after redefinition" {
    bdwgc.init();
    defer bdwgc.deinit();
    const allocator = std.testing.allocator;
    var parser = try cora.prism.Parser.init(allocator,
        \\class SharedDispatchProbe
        \\  def value(x, scale: 1); (10 + x) * scale; end
        \\end
        \\def shared_pair(obj); [obj.value(1, scale: 2), obj.value(3)]; end
        \\$shared_probe = SharedDispatchProbe.new
        \\shared_pair($shared_probe)
    , null);
    defer parser.deinit();
    var program = try cora.compiler.Compiler.compile(allocator, &parser, 1);
    defer program.deinit();
    var vm = cora.vm.VM.initEmpty(allocator, cora.gc_allocator.scanned, cora.gc_allocator.atomic, std.testing.io, std.testing.environ);
    defer vm.deinit();
    try vm.prepare(&program);
    const result = try vm.run();
    try std.testing.expectEqual(@as(i64, 22), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 13), result.toArrayObject().elements.items[1].toInteger());

    var pair: ?*cora.chunk.Chunk = null;
    var iter = program.child_chunks.valueIterator();
    while (iter.next()) |ptr| {
        if (std.mem.eql(u8, ptr.*.name, "shared_pair")) pair = ptr.*;
    }
    const pair_chunk = pair orelse return error.TestUnexpectedResult;
    const original = pair_chunk.callsite_caches.items[0].?;
    try std.testing.expect(original == pair_chunk.callsite_caches.items[1].?);

    const replaced = try vm.evalSource(
        \\class SharedDispatchProbe
        \\  def value(x, scale: 1); (100 + x) * scale; end
        \\end
        \\GC.start
        \\shared_pair($shared_probe)
    , null);
    try std.testing.expectEqual(@as(i64, 202), replaced.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 103), replaced.toArrayObject().elements.items[1].toInteger());
    try std.testing.expect(original != pair_chunk.callsite_caches.items[0].?);
    try std.testing.expect(pair_chunk.callsite_caches.items[0].? == pair_chunk.callsite_caches.items[1].?);

    const rooted_chunks = vm.callsite_cache_chunks.count();
    for (0..20) |_| _ = try vm.evalSource("1.to_s; GC.start", null);
    try std.testing.expect(vm.callsite_cache_chunks.count() <= rooted_chunks);

    vm.method_state_version = std.math.maxInt(u64);
    vm.bumpMethodStateVersion();
    try std.testing.expect(pair_chunk.callsite_caches.items[0] == null);
    try std.testing.expect(pair_chunk.callsite_caches.items[1] == null);
    for (vm.shared_callsite_caches) |cached| try std.testing.expect(cached == null);
    const after_wrap = try vm.evalSource("shared_pair($shared_probe)[0]", null);
    try std.testing.expectEqual(@as(i64, 202), after_wrap.toInteger());
}

test "call-site caches survive collection and distinguish inherited class methods" {
    const result = try evalCode(
        \\left = Class.new { def self.token; :left; end }
        \\right = Class.new { def self.token; :right; end }
        \\def shared_class_first(klass); klass.token; end
        \\def shared_class_second(klass); klass.token; end
        \\raise "class dispatch" unless shared_class_first(Class.new(left)) == :left
        \\raise "class dispatch" unless shared_class_second(Class.new(right)) == :right
        \\class SharedStable
        \\  def value; 42; end
        \\end
        \\def shared_stable_site(obj); obj.value; end
        \\stable = SharedStable.new
        \\5.times do
        \\  raise "stable dispatch" unless shared_stable_site(stable) == 42
        \\  1000.times do |i|
        \\    other = Class.new
        \\    other.define_singleton_method(:value) { i }
        \\    raise "singleton dispatch" unless other.value == i
        \\  end
        \\  GC.start
        \\  raise "collected dispatch" unless shared_stable_site(stable) == 42
        \\end
        \\true
    );
    try std.testing.expect(result.isTrue());
}

test "block break - basic with value" {
    const result = try evalCode(
        \\def each_test
        \\  yield 1
        \\  yield 2
        \\  yield 3
        \\  99
        \\end
        \\
        \\result = each_test do |x|
        \\  break 42 if x == 2
        \\  x
        \\end
        \\result
    );
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
}

test "block break - without value returns nil" {
    const result = try evalCode(
        \\def each_test
        \\  yield 1
        \\  yield 2
        \\  99
        \\end
        \\
        \\result = each_test do |x|
        \\  break if x == 1
        \\end
        \\result
    );
    try std.testing.expect(result.isNil());
}

test "block break - stops execution immediately" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const eval_result = test_helper.evalCodeWithOutput(
        \\def each_test
        \\  yield 1
        \\  yield 2
        \\  yield 3
        \\end
        \\
        \\each_test do |x|
        \\  break if x == 2
        \\  puts x
        \\end
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(eval_result.err == null);
    try std.testing.expectEqualStrings("1\n", eval_result.stdout);
}

test "block break - method doesn't continue after yield" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const eval_result = test_helper.evalCodeWithOutput(
        \\def test_method
        \\  puts 1
        \\  yield
        \\  puts 2
        \\  yield
        \\  puts 3
        \\end
        \\
        \\test_method do
        \\  break
        \\end
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(eval_result.err == null);
    // Should only print 1, not 2 or 3
    try std.testing.expectEqualStrings("1\n", eval_result.stdout);
}

test "block break - nested blocks use innermost" {
    const result = try evalCode(
        \\def outer
        \\  yield
        \\  99
        \\end
        \\
        \\def inner
        \\  yield
        \\  88
        \\end
        \\
        \\result = outer do
        \\  inner do
        \\    break 42
        \\  end
        \\end
        \\result
    );
    // Break from inner block should return 42 from inner, not outer
    // Outer continues and returns 99
    try std.testing.expectEqual(@as(i64, 99), result.toInteger());
}

test "block break - forwarded block exits the receiving method" {
    const result = try evalCode(
        \\def inner
        \\  yield
        \\end
        \\
        \\def outer(&block)
        \\  inner(&block)
        \\  :continued
        \\end
        \\
        \\outer { break :stopped }
    );
    try std.testing.expect(result.isSymbol());
    try std.testing.expectEqualStrings("stopped", result.toSymbolObject().name);
}

test "block break - forwarded through nested builtins exits the original call site" {
    const result = try evalCode(
        \\def receive
        \\  yield
        \\  :continued
        \\end
        \\send(:send, :receive) { break :stopped }
    );
    try std.testing.expect(result.isSymbol());
    try std.testing.expectEqualStrings("stopped", result.toSymbolObject().name);
}

test "block break - forwarded through Class#new exits the original call site" {
    const result = try evalCode(
        \\klass = Class.new do
        \\  def initialize
        \\    yield
        \\    :continued
        \\  end
        \\end
        \\klass.new { break :stopped }
    );
    try std.testing.expect(result.isSymbol());
    try std.testing.expectEqualStrings("stopped", result.toSymbolObject().name);
}

test "block break - proc call raises after its original call site returned" {
    const result = try evalCode(
        \\def orphaned_break
        \\  saved = proc { break :bad }
        \\  begin
        \\    saved.call
        \\  rescue => error
        \\    [error.class.name, error.message]
        \\  end
        \\end
        \\orphaned_break
    );
    try std.testing.expect(result.isArray());
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqualStrings("LocalJumpError", values[0].toStringObject().str);
    try std.testing.expectEqualStrings("break from proc-closure", values[1].toStringObject().str);
}

test "block break - different from loop break" {
    const result = try evalCode(
        \\def test
        \\  yield
        \\  77
        \\end
        \\
        \\result = test do
        \\  x = 0
        \\  while x == 0
        \\    x = 1
        \\    break
        \\  end
        \\  55
        \\end
        \\result
    );
    // Loop break exits loop, block continues and returns 55 to yield,
    // but the method continues and returns 77
    try std.testing.expectEqual(@as(i64, 77), result.toInteger());
}
