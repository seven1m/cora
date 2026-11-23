const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

// --- Enumerator.new with generator ---

test "Enumerator.new with yielder" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\e = Enumerator.new { |y| y << 1; y << 2; y << 3 }
        \\e.each { |v| puts v }
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("1\n2\n3\n", result.stdout);
}

test "Enumerator.new with next" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\e = Enumerator.new { |y| y << "a"; y << "b"; y << "c" }
        \\puts e.next
        \\puts e.next
        \\puts e.next
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("a\nb\nc\n", result.stdout);
}

test "Enumerator.new next raises StopIteration" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\e = Enumerator.new { |y| y << 1 }
        \\puts e.next
        \\begin
        \\  e.next
        \\  puts "should not reach"
        \\rescue StopIteration
        \\  puts "stopped"
        \\end
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("1\nstopped\n", result.stdout);
}

// --- Method-based enumerator (Array#each without block) ---

test "Array#each without block returns Enumerator" {
    const result = try evalCode("[1, 2, 3].each");
    try std.testing.expect(result.isEnumerator());
}

test "Array#each enumerator round-trip" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\[1, 2, 3].each.each { |v| puts v }
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("1\n2\n3\n", result.stdout);
}

test "Array#each enumerator next" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\e = [10, 20, 30].each
        \\puts e.next
        \\puts e.next
        \\puts e.next
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("10\n20\n30\n", result.stdout);
}

test "Array#map without block returns Enumerator" {
    const result = try evalCode("[1, 2, 3].map");
    try std.testing.expect(result.isEnumerator());
}

test "Array#each_with_index without block returns Enumerator" {
    const result = try evalCode("[1, 2, 3].each_with_index");
    try std.testing.expect(result.isEnumerator());
}

test "Enumerator map uses internal iteration without consuming an external cursor" {
    const result = try evalCode(
        \\class EnumeratorMapSource
        \\  attr_reader :fibers, :ensures
        \\  def initialize
        \\    @fibers = []
        \\    @ensures = 0
        \\  end
        \\  def each
        \\    @fibers << Fiber.current
        \\    yield 1
        \\    yield 2
        \\    yield 3
        \\  ensure
        \\    @ensures += 1
        \\  end
        \\end
        \\source = EnumeratorMapSource.new
        \\iterator = source.to_enum
        \\caller_fiber = Fiber.current
        \\first = iterator.next
        \\peeked = iterator.peek
        \\mapped = iterator.map { |n| n * 10 }
        \\collected = iterator.collect { |n| n + 1 }
        \\peek_after = iterator.peek
        \\rest = [iterator.next, iterator.next]
        \\finished = begin iterator.next; false; rescue StopIteration; true; end
        \\first == 1 && peeked == 2 && mapped == [10, 20, 30] && collected == [2, 3, 4] &&
        \\  peek_after == 2 && rest == [2, 3] && finished && source.ensures == 3 &&
        \\  !source.fibers[0].equal?(caller_fiber) && source.fibers[1].equal?(caller_fiber) &&
        \\  source.fibers[2].equal?(caller_fiber)
    );
    try std.testing.expect(result.isTrue());
}

test "Enumerator map preserves zero and multiple yield arguments and callback returns" {
    const result = try evalCode(
        \\returns = []
        \\iterator = Enumerator.new do |yielder|
        \\  returns << yielder.yield
        \\  returns << yielder.yield(1)
        \\  returns << yielder.yield(2, 3)
        \\  returns << yielder.yield([4, 5])
        \\end
        \\mapped = iterator.map { |*args| args }
        \\pairs = Enumerator.new { |y| y.yield(1, 2) }
        \\strict = pairs.map(&->(a, b) { a + b })
        \\zero = Enumerator.new { |y| y.yield }.map(&-> { :zero })
        \\wrong = begin Enumerator.new { |y| y.yield([1, 2]) }.map(&->(a, b) { a + b }); false; rescue ArgumentError; true; end
        \\mapped == [[], [1], [2, 3], [[4, 5]]] && returns == [nil, nil, nil, nil] &&
        \\  strict == [3] && zero == [:zero] && wrong
    );
    try std.testing.expect(result.isTrue());
}

test "Enumerator map preserves source and block exceptions and runs ensure" {
    const result = try evalCode(
        \\ensures = []
        \\failure = StopIteration.new("from generator")
        \\iterator = Enumerator.new do |y|
        \\  begin
        \\    y << 1
        \\    raise failure
        \\  ensure
        \\    ensures << :source
        \\  end
        \\end
        \\caught = begin iterator.map { |n| n }; rescue StopIteration => error; error; end
        \\second = Enumerator.new do |y|
        \\  begin
        \\    y << 1
        \\    y << 2
        \\  ensure
        \\    ensures << :block
        \\  end
        \\end
        \\block_failure = RuntimeError.new("from block")
        \\block_caught = begin second.map { raise block_failure }; rescue RuntimeError => error; error; end
        \\caught.equal?(failure) && block_caught.equal?(block_failure) && ensures == [:source, :block]
    );
    try std.testing.expect(result.isTrue());
}

test "Enumerator map preserves break return throw and suspended nested callbacks" {
    const result = try evalCode(
        \\def enumerator_mapping_return(iterator)
        \\  iterator.map { return :returned }
        \\  :unreachable
        \\end
        \\ensures = []
        \\iterator = Enumerator.new do |y|
        \\  begin
        \\    y << 1
        \\    y << 2
        \\  ensure
        \\    ensures << :ensured
        \\  end
        \\end
        \\broken = iterator.map { break :broken }
        \\returned = enumerator_mapping_return(iterator)
        \\thrown = catch(:map_done) { iterator.map { throw :map_done, :thrown } }
        \\fiber = Fiber.new do
        \\  iterator.map do |n|
        \\    Fiber.yield n
        \\    GC.start
        \\    [n].each.map { |value| value * 10 }.first
        \\  end
        \\end
        \\first = fiber.resume
        \\GC.start
        \\second = fiber.resume
        \\GC.start
        \\result = fiber.resume
        \\broken == :broken && returned == :returned && thrown == :thrown &&
        \\  first == 1 && second == 2 && result == [10, 20] && ensures == [:ensured] * 4
    );
    try std.testing.expect(result.isTrue());
}

test "Enumerator map inherits sized fallback and respects overridden each" {
    const result = try evalCode(
        \\iterator = [1, 2, 3].each
        \\mapping = iterator.map
        \\fallback = mapping.is_a?(Enumerator) && mapping.size == 3 && mapping.each { |n| n * 2 } == [2, 4, 6]
        \\def iterator.each
        \\  yield :custom
        \\  self
        \\end
        \\exhausted = [1].each
        \\exhausted.next
        \\begin exhausted.next; rescue StopIteration; end
        \\replayed = exhausted.map { |n| n }
        \\still_done = begin exhausted.next; false; rescue StopIteration; true; end
        \\fallback && iterator.map { |n| n } == [:custom] &&
        \\  iterator.collect { |n| n } == [:custom] && replayed == [1] && still_done
    );
    try std.testing.expect(result.isTrue());
}

test "Enumerator map preserves Hash and Struct pair block arity" {
    const result = try evalCode(
        \\record = Struct.new(:name, :number).new("sample", 7)
        \\hash = {name: "sample", number: 7}
        \\checks = [record, hash].map do |object|
        \\  pairs = [[:name, "sample"], [:number, 7]]
        \\  direct = []
        \\  object.each_pair { |pair| direct << pair }
        \\  rest = []
        \\  object.each_pair { |*args| rest << args }
        \\  lambda_pairs = []
        \\  object.each_pair(&->(pair) { lambda_pairs << pair })
        \\  mapped = object.each_pair.map { |pair| pair }
        \\  strict_mapped = object.each_pair.map(&->(key, value) { [key, value] })
        \\  direct == pairs && rest == pairs.map { |pair| [pair] } && lambda_pairs == pairs &&
        \\    mapped == pairs && strict_mapped == pairs
        \\end
        \\checks.all?
    );
    try std.testing.expect(result.isTrue());
}

test "Enumerator map pair iteration keeps direct lambdas strict" {
    const sources = [_][]const u8{
        "Struct.new(:name).new(1).each_pair(&->(key, value) { nil })",
        "{name: 1}.each_pair(&->(key, value) { nil })",
    };
    for (sources) |code| {
        var stdout_buf: [4096]u8 = undefined;
        var stderr_buf: [4096]u8 = undefined;
        const result = evalCodeWithOutput(code, &stdout_buf, &stderr_buf);
        try std.testing.expectEqual(error.UnhandledException, result.err.?);
        try std.testing.expect(std.mem.indexOf(u8, result.stderr, "ArgumentError") != null);
    }
}

// --- Rewind ---

test "Enumerator#rewind" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\e = [1, 2, 3].each
        \\puts e.next
        \\puts e.next
        \\e.rewind
        \\puts e.next
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("1\n2\n1\n", result.stdout);
}

// --- Yielder chaining ---

test "Yielder << chaining" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\e = Enumerator.new { |y| y << 1 << 2 << 3 }
        \\e.each { |v| puts v }
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("1\n2\n3\n", result.stdout);
}

// --- Hash#each without block ---

test "Hash#each without block returns Enumerator" {
    const result = try evalCode("{a: 1}.each");
    try std.testing.expect(result.isEnumerator());
}

// --- Integer#times without block ---

test "Integer#times without block returns Enumerator" {
    const result = try evalCode("3.times");
    try std.testing.expect(result.isEnumerator());
}

test "Integer#times enumerator next" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\e = 3.times
        \\puts e.next
        \\puts e.next
        \\puts e.next
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("0\n1\n2\n", result.stdout);
}

// --- Enumerator#each without block returns self ---

test "Enumerator#each without block returns self" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\e = [1, 2, 3].each
        \\e2 = e.each
        \\puts e2.next
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("1\n", result.stdout);
}

// --- Inspect ---

test "Enumerator#inspect for method-based" {
    const result = try evalCode("[1, 2, 3].each.inspect");
    try std.testing.expect(result.isString());
    const str = result.toStringObject().str;
    try std.testing.expect(std.mem.indexOf(u8, str, "Enumerator") != null);
    try std.testing.expect(std.mem.indexOf(u8, str, "each") != null);
}

test "ArithmeticSequence exposes range bounds and step and inspects its origin" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\a = (1..10).step(2)
        \\p [a.begin, a.end, a.step, a.inspect]
        \\b = (1..).step
        \\p [b.begin, b.end, b.step, b.inspect]
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("[1, 10, 2, \"((1..10).step(2))\"]\n[1, nil, 1, \"((1..).step)\"]\n", result.stdout);
}

test "Array#each Enumerator#size returns enumerable size" {
    const result = try evalCode("[1, 2, 3].each.size");
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 3), result.toInteger());
}

test "to_enum next exposes multi-arg yields as arrays" {
    const result = try evalCode(
        \\o = Object.new
        \\def o.each
        \\  yield :a
        \\  yield :b1, :b2
        \\  yield [:c]
        \\  yield :d1, :d2, :d3
        \\end
        \\e = o.to_enum
        \\[e.next, e.next, e.next, e.next]
    );
    try std.testing.expect(result.isArray());

    const values = result.toArrayObject().elements.items;
    try std.testing.expect(values[0].isSymbol());
    try std.testing.expectEqualStrings("a", values[0].toSymbolObject().name);

    try std.testing.expect(values[1].isArray());
    try std.testing.expectEqual(@as(usize, 2), values[1].toArrayObject().elements.items.len);
    try std.testing.expect(values[1].toArrayObject().elements.items[0].isSymbol());
    try std.testing.expect(values[1].toArrayObject().elements.items[1].isSymbol());
    try std.testing.expectEqualStrings("b1", values[1].toArrayObject().elements.items[0].toSymbolObject().name);
    try std.testing.expectEqualStrings("b2", values[1].toArrayObject().elements.items[1].toSymbolObject().name);

    try std.testing.expect(values[2].isArray());
    try std.testing.expectEqual(@as(usize, 1), values[2].toArrayObject().elements.items.len);
    try std.testing.expect(values[2].toArrayObject().elements.items[0].isSymbol());
    try std.testing.expectEqualStrings("c", values[2].toArrayObject().elements.items[0].toSymbolObject().name);

    try std.testing.expect(values[3].isArray());
    try std.testing.expectEqual(@as(usize, 3), values[3].toArrayObject().elements.items.len);
    try std.testing.expect(values[3].toArrayObject().elements.items[0].isSymbol());
    try std.testing.expect(values[3].toArrayObject().elements.items[1].isSymbol());
    try std.testing.expect(values[3].toArrayObject().elements.items[2].isSymbol());
    try std.testing.expectEqualStrings("d1", values[3].toArrayObject().elements.items[0].toSymbolObject().name);
    try std.testing.expectEqualStrings("d2", values[3].toArrayObject().elements.items[1].toSymbolObject().name);
    try std.testing.expectEqualStrings("d3", values[3].toArrayObject().elements.items[2].toSymbolObject().name);
}

// --- StopIteration exception hierarchy ---

test "StopIteration is a kind of IndexError" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\begin
        \\  raise StopIteration
        \\rescue IndexError
        \\  puts "caught"
        \\end
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("caught\n", result.stdout);
}

// --- Array#each round-trip ---

test "Array#each enumerator round-trip with each" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\[10, 20, 30].each.each { |v| puts v }
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("10\n20\n30\n", result.stdout);
}

// --- Infinite enumerator ---

test "Enumerator infinite generator with next" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\e = Enumerator.new { |y| i = 0; loop { i = i + 1; y << i } }
        \\puts e.next
        \\puts e.next
        \\puts e.next
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("1\n2\n3\n", result.stdout);
}

// --- Integer#upto without block ---

test "Integer#upto without block returns Enumerator" {
    const result = try evalCode("1.upto(5)");
    try std.testing.expect(result.isEnumerator());
}

test "Integer#upto enumerator next" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\e = 1.upto(3)
        \\puts e.next
        \\puts e.next
        \\puts e.next
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("1\n2\n3\n", result.stdout);
}

test "Chain rewind tolerates reinitialization during iteration" {
    const result = try evalCode(
        \\chain = Enumerator::Chain.new([1], [2])
        \\chain.each { |item| chain.send(:initialize) if item == 1 }
        \\chain.rewind.equal?(chain) && chain.inspect == "#<Enumerator::Chain: []>"
    );
    try std.testing.expectEqual(true, result.toBool());
}
