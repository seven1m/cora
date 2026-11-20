const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Enumerable short circuit methods use internal iteration and unwind each on early exit" {
    const result = try evalCode(
        \\class SearchSource
        \\  include Enumerable
        \\  attr_reader :events
        \\  def initialize
        \\    @events = []
        \\  end
        \\  def each
        \\    @events << (Fiber.current.equal?($search_fiber) ? :same_fiber : :other_fiber)
        \\    yield 1, 2
        \\    @events << :continued
        \\    yield 3, 4
        \\    @events << :exhausted
        \\  ensure
        \\    @events << :ensured
        \\  end
        \\end
        \\$search_fiber = Fiber.current
        \\checks = [:find, :find_index, :include?, :any?, :all?, :none?, :one?, :first, :take, :take_while].map do |name|
        \\  source = SearchSource.new
        \\  result = if name == :include?
        \\    source.include?([1, 2])
        \\  elsif name == :first
        \\    source.first
        \\  elsif name == :take
        \\    source.take(1)
        \\  elsif name == :take_while
        \\    source.take_while { |a, b| a < 3 }
        \\  else
        \\    source.public_send(name) { |*values| name != :all? }
        \\  end
        \\  expected = {find: [1, 2], find_index: 0, include?: true, any?: true, all?: false, none?: false, one?: false, first: [1, 2], take: [[1, 2]], take_while: [[1, 2]]}[name]
        \\  events = (name == :one? || name == :take_while) ? [:same_fiber, :continued, :ensured] : [:same_fiber, :ensured]
        \\  result == expected && source.events == events
        \\end
        \\source = SearchSource.new
        \\prefix = source.first(1) == [[1, 2]] && source.events == [:same_fiber, :ensured]
        \\source = SearchSource.new
        \\zero = source.take(0) == [] && source.events.empty?
        \\source = SearchSource.new
        \\enum = source.to_enum
        \\external = enum.next == [1, 2] && source.events == [:other_fiber]
        \\enum.next
        \\begin
        \\  enum.next
        \\rescue StopIteration
        \\end
        \\checks.all? && prefix && zero && external && source.events == [:other_fiber, :continued, :exhausted, :ensured]
    );
    try std.testing.expect(result.isTruthy());
}

test "Enumerable internal iteration preserves nested searches and user control flow" {
    const result = try evalCode(
        \\events = []
        \\source = Object.new
        \\source.extend(Enumerable)
        \\source.define_singleton_method(:each) do |&block|
        \\  begin
        \\    block.call(nil)
        \\    block.call(2)
        \\  ensure
        \\    events << :ensured
        \\  end
        \\end
        \\fallback = -> { raise "unexpected fallback" }
        \\found_nil = source.find(fallback) { [true].find { true } }
        \\broken = source.find { break :broken }
        \\thrown = catch(:done) { source.any? { throw :done, :thrown } }
        \\found_nil.nil? && broken == :broken && thrown == :thrown && events == [:ensured, :ensured, :ensured]
    );
    try std.testing.expect(result.isTruthy());
}

test "Enumerable collectors use internal iteration in the caller fiber" {
    const result = try evalCode(
        \\class CollectSource
        \\  include Enumerable
        \\  attr_reader :events
        \\  def initialize
        \\    @events = []
        \\  end
        \\  def each
        \\    @events << (Fiber.current.equal?($collect_fiber) ? :same : :other)
        \\    GC.start
        \\    yield 2
        \\    yield 1
        \\    yield 3
        \\    :ignored_each_result
        \\  ensure
        \\    @events << :ensured
        \\  end
        \\end
        \\$collect_fiber = Fiber.current
        \\checks = [:filter_map, :each_with_object, :sort_by].map do |name|
        \\  source = CollectSource.new
        \\  memo = []
        \\  result = case name
        \\  when :filter_map
        \\    source.filter_map { |n| n * 10 if n.even? }
        \\  when :each_with_object
        \\    source.each_with_object(memo) { |n, out| out << n }
        \\  else
        \\    source.sort_by { |n| -n }
        \\  end
        \\  expected = {filter_map: [20], each_with_object: [2, 1, 3], sort_by: [3, 2, 1]}[name]
        \\  result == expected && source.events == [:same, :ensured] &&
        \\    (name != :each_with_object || result.equal?(memo))
        \\end
        \\checks.all?
    );
    try std.testing.expect(result.isTrue());
}

test "Enumerable collectors preserve yield packing and callback return values" {
    const result = try evalCode(
        \\class CollectYields
        \\  include Enumerable
        \\  attr_reader :results
        \\  def each
        \\    @results = []
        \\    @results << (yield)
        \\    @results << (yield 1, 2)
        \\    :ignored
        \\  end
        \\end
        \\filtered = CollectYields.new
        \\values = filtered.filter_map { |*args| args.empty? ? :empty : args }
        \\sorted = CollectYields.new
        \\seen = []
        \\order = sorted.sort_by { |*args| seen << args; args.length }
        \\with_object = CollectYields.new
        \\memo = []
        \\returned = with_object.each_with_object(memo) { |element, out| out << element; :from_block }
        \\values == [:empty, [1, 2]] && filtered.results == [nil, nil] &&
        \\  order == [nil, [1, 2]] && seen == [[], [[1, 2]]] && sorted.results == [nil, nil] &&
        \\  returned.equal?(memo) && memo == [nil, [1, 2]] && with_object.results == [:from_block, :from_block]
    );
    try std.testing.expect(result.isTrue());
}

test "Enumerable collectors handle strict lambda yield arity" {
    const result = try evalCode(
        \\class CollectPair
        \\  include Enumerable
        \\  def each
        \\    yield 1, 2
        \\  end
        \\end
        \\class CollectZero
        \\  include Enumerable
        \\  def each
        \\    yield
        \\  end
        \\end
        \\class CollectSingleArray
        \\  include Enumerable
        \\  def each
        \\    yield [1, 2]
        \\  end
        \\end
        \\pair = CollectPair.new
        \\seen = []
        \\sorted = pair.sort_by(&->(a, b) { a + b })
        \\rest_sorted = pair.sort_by(&->(*args) { seen << args; 0 })
        \\filtered = pair.filter_map(&->(a, b) { a + b })
        \\raw = pair.filter_map(&->(*args) { args })
        \\filter_error = begin pair.filter_map(&->(one) { one }); false; rescue ArgumentError; true; end
        \\single_error = begin CollectSingleArray.new.sort_by(&->(a, b) { 0 }); false; rescue ArgumentError; true; end
        \\sorted == [[1, 2]] && rest_sorted == [[1, 2]] && seen == [[[1, 2]]] &&
        \\  filtered == [3] && raw == [[1, 2]] && filter_error && single_error &&
        \\  CollectZero.new.sort_by(&-> { 0 }) == [nil] && CollectZero.new.filter_map(&-> { :zero }) == [:zero]
    );
    try std.testing.expect(result.isTrue());
}

test "Enumerable collectors unwind each ensures for break return and throw" {
    const result = try evalCode(
        \\class CollectUnwind
        \\  include Enumerable
        \\  attr_reader :ensures
        \\  def initialize
        \\    @ensures = 0
        \\  end
        \\  def each
        \\    yield 1
        \\    yield 2
        \\  ensure
        \\    @ensures += 1
        \\  end
        \\end
        \\def collect_method_return(source, name, args)
        \\  source.public_send(name, *args) { return :returned }
        \\  :unreachable
        \\end
        \\checks = [:filter_map, :each_with_object, :sort_by].map do |name|
        \\  args = name == :each_with_object ? [[]] : []
        \\  source = CollectUnwind.new
        \\  broken = source.public_send(name, *args) { break :broken }
        \\  returned = collect_method_return(source, name, args)
        \\  thrown = catch(:collect_done) { source.public_send(name, *args) { throw :collect_done, :thrown } }
        \\  broken == :broken && returned == :returned && thrown == :thrown && source.ensures == 3
        \\end
        \\checks.all?
    );
    try std.testing.expect(result.isTrue());
}

test "Enumerable collectors propagate source StopIteration and block failures" {
    const result = try evalCode(
        \\class CollectFailure
        \\  include Enumerable
        \\  attr_reader :ensures
        \\  def initialize(failure)
        \\    @failure = failure
        \\    @ensures = 0
        \\  end
        \\  def each
        \\    yield 1
        \\    raise @failure if @failure
        \\  ensure
        \\    @ensures += 1
        \\  end
        \\end
        \\checks = [:filter_map, :each_with_object, :sort_by].map do |name|
        \\  args = name == :each_with_object ? [[]] : []
        \\  failure = StopIteration.new("from source")
        \\  source = CollectFailure.new(failure)
        \\  caught = begin source.public_send(name, *args) { 1 }; rescue StopIteration => error; error; end
        \\  block_failure = RuntimeError.new("from block")
        \\  second = CollectFailure.new(nil)
        \\  block_caught = begin second.public_send(name, *args) { raise block_failure }; rescue RuntimeError => error; error; end
        \\  caught.equal?(failure) && source.ensures == 1 && block_caught.equal?(block_failure) && second.ensures == 1
        \\end
        \\checks.all?
    );
    try std.testing.expect(result.isTrue());
}

test "Enumerable collectors retain nested callback state across Fiber yield and GC" {
    const result = try evalCode(
        \\fiber = Fiber.new do
        \\  mapped = [3, 1, 2].filter_map do |n|
        \\    Fiber.yield [:map, n]
        \\    GC.start
        \\    [n].filter_map { |inner| inner * 2 }.first
        \\  end
        \\  sorted = mapped.sort_by do |n|
        \\    Fiber.yield [:key, n]
        \\    -n
        \\  end
        \\  sorted.each_with_object([]) do |n, out|
        \\    Fiber.yield [:memo, n]
        \\    GC.start
        \\    out << n
        \\  end
        \\end
        \\seen = []
        \\while fiber.alive?
        \\  seen << fiber.resume
        \\  GC.start
        \\end
        \\seen == [[:map, 3], [:map, 1], [:map, 2], [:key, 6], [:key, 2], [:key, 4],
        \\         [:memo, 6], [:memo, 4], [:memo, 2], [6, 4, 2]]
    );
    try std.testing.expect(result.isTrue());
}

test "Enumerable collectors preserve enumerator fallback sizes and overridden each" {
    const result = try evalCode(
        \\array = [99]
        \\def array.each
        \\  yield 4
        \\  yield 2
        \\  :ignored
        \\end
        \\memo = []
        \\filtered = array.filter_map { |n| n }
        \\sorted = array.sort_by { |n| n }
        \\returned = array.each_with_object(memo) { |n, out| out << n }
        \\filter_enum = [2, 1].filter_map
        \\sort_enum = [2, 1].sort_by
        \\object_enum = [2, 1].each_with_object([])
        \\filtered == [4, 2] && sorted == [2, 4] && returned.equal?(memo) && memo == [4, 2] &&
        \\  [filter_enum.size, sort_enum.size, object_enum.size] == [2, 2, 2] &&
        \\  filter_enum.each { |n| n * 2 } == [4, 2] && sort_enum.each { |n| n } == [1, 2] &&
        \\  object_enum.each { |n, out| out << n } == [2, 1]
    );
    try std.testing.expect(result.isTrue());
}

test "Array#replace preserves its elements when replacing itself" {
    const result = try evalCode(
        \\a = [1, 2]
        \\wrapper = Object.new
        \\wrapper.define_singleton_method(:to_ary) { a }
        \\a.replace(a)
        \\a.replace(wrapper)
    );
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 2), items.len);
    try std.testing.expectEqual(@as(i64, 1), items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 2), items[1].toInteger());
}

test "Array#sample handles a random generator mutating the receiver" {
    const result = try evalCode(
        \\a = [1, 2, 3]
        \\random = Object.new
        \\random.define_singleton_method(:rand) { |n| a.pop; 0 }
        \\a.sample(2, random: random)
    );
    try std.testing.expect(result.isArray());
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 1), items.len);
    try std.testing.expectEqual(@as(i64, 1), items[0].toInteger());
}

test "Empty array" {
    const result = try evalCode("[]");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 0), result.toArrayObject().elements.items.len);
}

test "Array with integers" {
    const result = try evalCode("[1, 2, 3]");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 3), result.toArrayObject().elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 2), result.toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 3), result.toArrayObject().elements.items[2].toInteger());
}

test "Array with mixed types" {
    const result = try evalCode("[1, true, nil]");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 3), result.toArrayObject().elements.items.len);
    try std.testing.expect(result.toArrayObject().elements.items[0].isInteger());
    try std.testing.expect(result.toArrayObject().elements.items[1].isBool());
    try std.testing.expect(result.toArrayObject().elements.items[2].isNil());
}

test "Array << append" {
    const result = try evalCode(
        \\[1, 2] << 3
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 3), result.toArrayObject().elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 2), result.toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 3), result.toArrayObject().elements.items[2].toInteger());
}

test "Array << chaining" {
    const result = try evalCode(
        \\[1] << 2 << 3
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 3), result.toArrayObject().elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 2), result.toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 3), result.toArrayObject().elements.items[2].toInteger());
}

test "Nested arrays" {
    const result = try evalCode("[[1, 2], [3, 4]]");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 2), result.toArrayObject().elements.items.len);

    const first_array = result.toArrayObject().elements.items[0];
    try std.testing.expect(first_array.isArray());
    try std.testing.expectEqual(@as(usize, 2), first_array.toArrayObject().elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), first_array.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 2), first_array.toArrayObject().elements.items[1].toInteger());

    const second_array = result.toArrayObject().elements.items[1];
    try std.testing.expect(second_array.isArray());
    try std.testing.expectEqual(@as(usize, 2), second_array.toArrayObject().elements.items.len);
    try std.testing.expectEqual(@as(i64, 3), second_array.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 4), second_array.toArrayObject().elements.items[1].toInteger());
}

test "Array#inspect with integers" {
    const result = try evalCode("[1, 2, 3].inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "[1, 2, 3]", result.toStringObject().str);
}

test "Array#inspect with strings" {
    const result = try evalCode("[\"a\", \"b\"].inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "[\"a\", \"b\"]", result.toStringObject().str);
}

test "Array#inspect mixed types" {
    const result = try evalCode("[1, \"hi\", :foo, nil].inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "[1, \"hi\", :foo, nil]", result.toStringObject().str);
}

test "Array#inspect empty" {
    const result = try evalCode("[].inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "[]", result.toStringObject().str);
}

test "Array#inspect nested" {
    const result = try evalCode("[[1, 2], [3, 4]].inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "[[1, 2], [3, 4]]", result.toStringObject().str);
}

test "Array#inspect recursive" {
    const result = try evalCode(
        \\a = [1, 2, 3]
        \\a << a
        \\a.inspect
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "[1, 2, 3, [...]]", result.toStringObject().str);
}

test "Array#<=> handles recursive arrays" {
    var result = try evalCode(
        \\a = []
        \\a << a
        \\a <=> a
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 0), result.toInteger());

    result = try evalCode(
        \\a = [1, "two", 3.0]
        \\5.times { a << a }
        \\a <=> a
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 0), result.toInteger());
}

test "Array#hash matches eql? recursive array shapes" {
    const result = try evalCode(
        \\rec = []
        \\rec << rec
        \\[rec.hash, [rec].hash, [[rec]].hash]
    );
    try std.testing.expect(result.isArray());
    const hashes = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 3), hashes.len);
    try std.testing.expectEqual(hashes[0].toInteger(), hashes[1].toInteger());
    try std.testing.expectEqual(hashes[0].toInteger(), hashes[2].toInteger());
}

test "Array#hash matches through recursive hashes" {
    const result = try evalCode(
        \\h = {}
        \\rec = [h]
        \\h[:x] = rec
        \\[rec.hash, [h].hash, [{x: rec}].hash]
    );
    try std.testing.expect(result.isArray());
    const hashes = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 3), hashes.len);
    try std.testing.expectEqual(hashes[0].toInteger(), hashes[1].toInteger());
    try std.testing.expectEqual(hashes[0].toInteger(), hashes[2].toInteger());
}

test "Array#fill supports range form used by hash spec" {
    const result = try evalCode("[1, 2, 3, 4].fill('a', 0..2).inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "[\"a\", \"a\", \"a\", 4]", result.toStringObject().str);
}

test "Array#to_s" {
    const result = try evalCode("[1, 2, 3].to_s");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "[1, 2, 3]", result.toStringObject().str);
}

test "Array#size" {
    const result = try evalCode("[1, 2, 3].size");
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 3), result.toInteger());
}

test "Array#max returns the largest element or nil for empty arrays" {
    var result = try evalCode("[3, 1, 4, 2].max");
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 4), result.toInteger());

    result = try evalCode("[].max");
    try std.testing.expect(result.isNil());
}

test "Array#max uses the comparison block" {
    const result = try evalCode("[\"a\", \"bbb\", \"cc\"].max { |a, b| a.length <=> b.length }");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "bbb", result.toStringObject().str);
}

test "Array#map" {
    const result = try evalCode("[1, 2, 3].map { |x| x * 2 }");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 3), result.toArrayObject().elements.items.len);
    try std.testing.expectEqual(@as(i64, 2), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 4), result.toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 6), result.toArrayObject().elements.items[2].toInteger());
}

test "Array#flatten recursively expands nested arrays" {
    const result = try evalCode("[1, [2, [3]], 4].flatten");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 4), result.toArrayObject().elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 2), result.toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 3), result.toArrayObject().elements.items[2].toInteger());
    try std.testing.expectEqual(@as(i64, 4), result.toArrayObject().elements.items[3].toInteger());
}

test "Array#flatten raises on recursive arrays" {
    const result = try evalCode(
        \\a = []
        \\a << a
        \\begin
        \\  a.flatten
        \\rescue => e
        \\  [e.class == ArgumentError, e.message]
        \\end
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[0].toBool());
    try std.testing.expectEqualSlices(u8, "tried to flatten recursive array", result.toArrayObject().elements.items[1].toStringObject().str);
}

test "Array#uniq! removes duplicates in place and returns nil when unchanged" {
    var result = try evalCode("a = [1, 2, 1, 3]; [a.uniq!, a]");
    try std.testing.expect(result.isArray());
    try std.testing.expect(result.toArrayObject().elements.items[0].isArray());
    try std.testing.expect(result.toArrayObject().elements.items[1].isArray());
    try std.testing.expectEqual(@as(usize, 3), result.toArrayObject().elements.items[1].toArrayObject().elements.items.len);

    result = try evalCode("a = [1, 2, 3]; a.uniq!");
    try std.testing.expect(result.isNil());
}

test "Array#each propagates break value" {
    var result = try evalCode("a = [1, 2, 3]; a.each { |x| break :done if x == 2 }");
    try std.testing.expect(result.isSymbol());
    try std.testing.expectEqualSlices(u8, "done", result.toSymbolObject().name);

    result = try evalCode("a = [1, 2, 3]; a.each { break }");
    try std.testing.expect(result.isNil());
}

test "Array#- removes all rhs-equal elements and preserves lhs duplicates otherwise" {
    var result = try evalCode("[1, 1, 2, 3] - [1, 4]");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 2), result.toArrayObject().elements.items.len);
    try std.testing.expectEqual(@as(i64, 2), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 3), result.toArrayObject().elements.items[1].toInteger());

    result = try evalCode("[1, 2, 2, 3] - []");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 4), result.toArrayObject().elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 2), result.toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 2), result.toArrayObject().elements.items[2].toInteger());
    try std.testing.expectEqual(@as(i64, 3), result.toArrayObject().elements.items[3].toInteger());
}

test "Array iteration methods propagate non-local return from blocks" {
    var result = try evalCode(
        \\def foo
        \\  [3, 2, 1].reverse_each do |i|
        \\    return i * 2 if i == 2
        \\  end
        \\end
        \\foo
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 4), result.toInteger());

    result = try evalCode(
        \\def foo
        \\  [1, 2].select { |i| return 9 if i == 1 }
        \\end
        \\foo
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 9), result.toInteger());

    result = try evalCode(
        \\def foo
        \\  a = [1, 2, 3]
        \\  a.select! { |i| return 7 if i == 2; i.odd? }
        \\end
        \\foo
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 7), result.toInteger());
}

test "Array#find_all aliases #select" {
    const result = try evalCode("[1, 2, 3, 4].find_all(&:even?)");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 2), result.toArrayObject().elements.items.len);
    try std.testing.expectEqual(@as(i64, 2), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 4), result.toArrayObject().elements.items[1].toInteger());
}

test "Array#product builds cartesian products and yields self with block" {
    var result = try evalCode("[1, 2].product([3, 4]).inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "[[1, 3], [1, 4], [2, 3], [2, 4]]", result.toStringObject().str);

    result = try evalCode("a = [1, 2]; [a.product([3]) { |x| x }, a.product([]) { |x| x }]");
    try std.testing.expect(result.isArray());
    const pair = result.toArrayObject().elements.items;
    try std.testing.expect(pair[0].isArray());
    try std.testing.expect(pair[1].isArray());
    try std.testing.expectEqual(@intFromPtr(pair[0].toArrayObject()), @intFromPtr(pair[1].toArrayObject()));
}

test "Array#product coerces arguments and raises RangeError on overflow" {
    var result = try evalCode(
        \\class ProductArrayLike
        \\  def to_ary
        \\    [2, 3]
        \\  end
        \\end
        \\[1].product(ProductArrayLike.new).inspect
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "[[1, 2], [1, 3]]", result.toStringObject().str);

    result = try evalCode(
        \\a = (0..100).to_a
        \\begin
        \\  a.product(a, a, a, a, a, a, a, a, a, a)
        \\rescue => e
        \\  e.class == RangeError
        \\end
    );
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());
}

test "Array#max_by returns the element with the largest block result" {
    var result = try evalCode("[1, 2, 3].max_by { |n| -n }");
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 1), result.toInteger());

    result = try evalCode("[].max_by { |n| n }");
    try std.testing.expect(result.isNil());
}

test "Array#any?" {
    var result = try evalCode("[nil, false, 1].any?");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());

    result = try evalCode("[nil, false].any?");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(false, result.toBool());

    result = try evalCode("[1, 2, 3].any? { |x| x > 2 }");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());
}

test "Array#include?" {
    var result = try evalCode("[1, 2, 3].include?(2)");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());

    result = try evalCode("[1, 2, 3].include?(9)");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(false, result.toBool());
}

test "Array#[]= set and extend" {
    var result = try evalCode("a = [1, 2, 3]; a[1] = 9; a");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(i64, 9), result.toArrayObject().elements.items[1].toInteger());

    result = try evalCode("a = [1]; a[3] = 5; a.inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "[1, nil, nil, 5]", result.toStringObject().str);

    result = try evalCode("a = [1, 2, 3]; a[-1] = 7; a");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(i64, 7), result.toArrayObject().elements.items[2].toInteger());

    result = try evalCode("a = [1, 2, 3]; a[1, 0] = [9, 8]; a.inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "[1, 9, 8, 2, 3]", result.toStringObject().str);

    result = try evalCode("a = [1, 2, 3]; a[1, 1] = 9; a.inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "[1, 9, 3]", result.toStringObject().str);

    result = try evalCode(
        \\class SliceReplacement
        \\  def to_ary
        \\    [7, 8]
        \\  end
        \\end
        \\a = [1, 2, 3]
        \\a[1, 1] = SliceReplacement.new
        \\a.inspect
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "[1, 7, 8, 3]", result.toStringObject().str);

    result = try evalCode("a = [1, 2, 3]; a[5, 0] = 9; a.inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "[1, 2, 3, nil, nil, 9]", result.toStringObject().str);

    result = try evalCode(
        \\begin
        \\  a = [1, 2, 3]
        \\  a[1, -1] = 9
        \\rescue => e
        \\  [e.class == IndexError, e.message]
        \\end
    );
    try std.testing.expect(result.isArray());
    try std.testing.expect(result.toArrayObject().elements.items[0].toBool());
    try std.testing.expectEqualSlices(u8, "negative length (-1)", result.toArrayObject().elements.items[1].toStringObject().str);
}

test "Array#map! mutates in place" {
    const result = try evalCode("a = [1, 2, 3]; a.map! { |x| x + 10 }; a");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(i64, 11), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 12), result.toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 13), result.toArrayObject().elements.items[2].toInteger());
}

test "Array#& intersection" {
    const result = try evalCode("[1, 2, 2, 3] & [2, 3, 4]");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 2), result.toArrayObject().elements.items.len);
    try std.testing.expectEqual(@as(i64, 2), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 3), result.toArrayObject().elements.items[1].toInteger());
}

test "Array#| union" {
    const result = try evalCode("[1, 2, 2] | [2, 3, 1, 4]");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 4), result.toArrayObject().elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 2), result.toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 3), result.toArrayObject().elements.items[2].toInteger());
    try std.testing.expectEqual(@as(i64, 4), result.toArrayObject().elements.items[3].toInteger());
}

test "Array#pack integer directives" {
    var result = try evalCode("[1, 2, 255].pack('C*')");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "\x01\x02\xff", result.toStringObject().str);

    result = try evalCode("[0x1234].pack('n').unpack('C*').inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "[18, 52]", result.toStringObject().str);
}

test "Array#pack Unicode directive encodes MRI codepoints" {
    const result = try evalCode(
        \\unicode = [0, 65, 233, 0x1f600].pack("U*")
        \\surrogate = [0xd800].pack("U")
        \\mixed = [65, 66].pack("UC")
        \\error = begin
        \\  [-1].pack("U")
        \\rescue RangeError => raised
        \\  raised.message
        \\end
        \\[unicode.bytes, unicode.encoding.name, surrogate.bytes, surrogate.valid_encoding?, mixed.encoding.name, error]
    );
    const values = result.toArrayObject().elements.items;
    const unicode_bytes = values[0].toArrayObject().elements.items;
    const expected_unicode = [_]i64{ 0, 65, 195, 169, 240, 159, 152, 128 };
    for (unicode_bytes, expected_unicode) |byte, number| try std.testing.expectEqual(number, byte.toInteger());
    try std.testing.expectEqualStrings("UTF-8", values[1].toStringObject().str);
    const surrogate_bytes = values[2].toArrayObject().elements.items;
    const expected_surrogate = [_]i64{ 237, 160, 128 };
    for (surrogate_bytes, expected_surrogate) |byte, number| try std.testing.expectEqual(number, byte.toInteger());
    try std.testing.expect(!values[3].toBool());
    try std.testing.expectEqualStrings("ASCII-8BIT", values[4].toStringObject().str);
    try std.testing.expectEqualStrings("pack(U): value out of range", values[5].toStringObject().str);
}

test "Array#pack float directives honor respond_to_missing? for to_f" {
    const result = try evalCode(
        \\obj = Object.new
        \\def obj.respond_to_missing?(name, include_private = false)
        \\  name == :to_f || super
        \\end
        \\def obj.method_missing(name, *args, &block)
        \\  return 3.5 if name == :to_f
        \\  super
        \\end
        \\[obj].pack('G').bytesize
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 8), result.toInteger());
}

test "Array#dup dispatches initialize_dup and initialize_copy overrides" {
    var result = try evalCode(
        \\class ArrayDupHookSpec < Array
        \\  def initialize_dup(other)
        \\    @hook = :dup
        \\    super
        \\  end
        \\
        \\  def initialize_copy(other)
        \\    @copy = other[0]
        \\    super
        \\  end
        \\end
        \\
        \\source = ArrayDupHookSpec[7]
        \\source.instance_variable_set(:@kept, 9)
        \\duped = source.dup
        \\[duped.instance_variable_get(:@hook), duped.instance_variable_get(:@copy), duped.instance_variable_get(:@kept), duped[0], duped.class == ArrayDupHookSpec]
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqualSlices(u8, "dup", result.toArrayObject().elements.items[0].toSymbolObject().name);
    try std.testing.expectEqual(@as(i64, 7), result.toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 9), result.toArrayObject().elements.items[2].toInteger());
    try std.testing.expectEqual(@as(i64, 7), result.toArrayObject().elements.items[3].toInteger());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[4].toBool());
}

test "Array#dup can reach method_missing for initialize_copy after undef_method" {
    const result = try evalCode(
        \\class ArrayDupMissingSpec < Array
        \\  undef_method :initialize_copy
        \\
        \\  def respond_to_missing?(name, include_private = false)
        \\    name == :initialize_copy
        \\  end
        \\
        \\  def method_missing(name, *args)
        \\    replace([:mm])
        \\    self
        \\  end
        \\end
        \\
        \\ArrayDupMissingSpec[1, 2].dup == [:mm]
    );
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());
}

test "Array#clone dispatches initialize_clone, preserves frozen state, and copies singleton methods" {
    const result = try evalCode(
        \\class ArrayCloneHookSpec < Array
        \\  def initialize_clone(other)
        \\    @hook = :clone
        \\    super
        \\  end
        \\end
        \\
        \\source = ArrayCloneHookSpec[7]
        \\source.instance_variable_set(:@kept, 9)
        \\def source.special
        \\  :singleton
        \\end
        \\source.freeze
        \\cloned = source.clone
        \\[
        \\  cloned.instance_variable_get(:@hook),
        \\  cloned.instance_variable_get(:@kept),
        \\  cloned[0],
        \\  cloned.class == ArrayCloneHookSpec,
        \\  cloned.frozen?,
        \\  cloned.special
        \\]
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqualSlices(u8, "clone", result.toArrayObject().elements.items[0].toSymbolObject().name);
    try std.testing.expectEqual(@as(i64, 9), result.toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 7), result.toArrayObject().elements.items[2].toInteger());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[3].toBool());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[4].toBool());
    try std.testing.expectEqualSlices(u8, "singleton", result.toArrayObject().elements.items[5].toSymbolObject().name);
}

test "Array#pack string directives" {
    var result = try evalCode("['ab'].pack('A4')");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "ab  ", result.toStringObject().str);

    result = try evalCode("['ab'].pack('a4')");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "ab\x00\x00", result.toStringObject().str);

    result = try evalCode("['ab'].pack('Z4')");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "ab\x00\x00", result.toStringObject().str);

    result = try evalCode("['abc'].pack('H*')");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "\xab\xc0", result.toStringObject().str);

    result = try evalCode("['abc'].pack('h*')");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "\xba\x0c", result.toStringObject().str);
}

test "Array#pack cursor directives" {
    var result = try evalCode("[1, 2].pack('CXC')");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "\x02", result.toStringObject().str);

    result = try evalCode("[1, 2].pack('C@3C')");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "\x01\x00\x00\x02", result.toStringObject().str);
}

test "Array#join falls back to default representation for invalid to_s result" {
    const result = try evalCode(
        \\object = Object.new
        \\def object.to_s = nil
        \\[object].join.match?(/#<Object:0x[0-9a-f]+>/)
    );
    try std.testing.expect(result.isTrue());
}
