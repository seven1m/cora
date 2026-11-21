const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Fiber storage inherits keys and isolates assignments" {
    const result = try evalCode(
        \\Fiber[:example] = 1
        \\child = Fiber.new do
        \\  before = Fiber[:example]
        \\  Fiber[:example] = 2
        \\  [before, Fiber[:example]]
        \\end
        \\before_resume = Fiber[:example]
        \\child_values = child.resume
        \\[before_resume, child_values, Fiber[:example], Fiber.send(:[]=, :example, nil), Fiber[:example]]
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 1), values[0].toInteger());
    const child_values = values[1].toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 1), child_values[0].toInteger());
    try std.testing.expectEqual(@as(i64, 2), child_values[1].toInteger());
    try std.testing.expectEqual(@as(i64, 1), values[2].toInteger());
    try std.testing.expectEqual(@as(i64, 1), values[3].toInteger());
    try std.testing.expect(values[4].isNil());
}

test "Fiber.new does not invoke block until resume" {
    const result = try evalCode(
        \\invoked = false
        \\f = Fiber.new { invoked = true }
        \\invoked
    );
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(false, result.toBool());
}

test "Fiber.yield returns resume argument to the fiber" {
    const result = try evalCode(
        \\f = Fiber.new do
        \\  x = Fiber.yield
        \\  x
        \\end
        \\a = f.resume
        \\b = f.resume(99)
        \\[a, b]
    );
    try std.testing.expect(result.isArray());
    const elems = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 2), elems.len);
    try std.testing.expect(elems[0].isNil());
    try std.testing.expectEqual(@as(i64, 99), elems[1].toInteger());
}

test "Fiber preserves method local variables across yield and resume" {
    const result = try evalCode(
        \\def test_method
        \\  x = 42
        \\  yield
        \\  x
        \\end
        \\f = Fiber.new { test_method { Fiber.yield(:paused) } }
        \\a = f.resume
        \\b = f.resume
        \\[a, b]
    );
    try std.testing.expect(result.isArray());
    const elems = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 2), elems.len);
    try std.testing.expect(elems[0].isSymbol());
    try std.testing.expectEqualStrings("paused", elems[0].toSymbolObject().name);
    try std.testing.expectEqual(@as(i64, 42), elems[1].toInteger());
}

test "Fiber preserves a pending proc return across yield in ensure" {
    const result = try evalCode(
        \\fiber = Fiber.new do
        \\  lambda do
        \\    callback = proc do
        \\      begin
        \\        return :done
        \\      ensure
        \\        Fiber.yield :paused
        \\      end
        \\    end
        \\    callback.call
        \\  end.call
        \\end
        \\first = fiber.resume
        \\begin
        \\  outside = 2
        \\ensure
        \\  marker = :outside
        \\end
        \\[first, outside, marker, fiber.resume]
    );
    try std.testing.expect(result.isArray());
    const elems = result.toArrayObject().elements.items;
    try std.testing.expectEqualStrings("paused", elems[0].toSymbolObject().name);
    try std.testing.expectEqual(@as(i64, 2), elems[1].toInteger());
    try std.testing.expectEqualStrings("outside", elems[2].toSymbolObject().name);
    try std.testing.expectEqualStrings("done", elems[3].toSymbolObject().name);
}

test "Fiber preserves a pending block break across yield in ensure" {
    const result = try evalCode(
        \\fiber = Fiber.new do
        \\  [1].each do
        \\    begin
        \\      break :broken
        \\    ensure
        \\      Fiber.yield :paused
        \\    end
        \\  end
        \\end
        \\[fiber.resume, 1 + 1, fiber.resume]
    );
    try std.testing.expect(result.isArray());
    const elems = result.toArrayObject().elements.items;
    try std.testing.expectEqualStrings("paused", elems[0].toSymbolObject().name);
    try std.testing.expectEqual(@as(i64, 2), elems[1].toInteger());
    try std.testing.expectEqualStrings("broken", elems[2].toSymbolObject().name);
}

test "Fiber keeps rescued exceptions local across yield" {
    const result = try evalCode(
        \\fiber = Fiber.new do
        \\  begin
        \\    raise "inside"
        \\  rescue
        \\    Fiber.yield $!.message
        \\    $!.message
        \\  end
        \\end
        \\first = fiber.resume
        \\begin
        \\  raise "outside"
        \\rescue
        \\  [first, $!.message, fiber.resume, $!.message]
        \\end
    );
    try std.testing.expect(result.isArray());
    const elems = result.toArrayObject().elements.items;
    try std.testing.expectEqualStrings("inside", elems[0].toStringObject().str);
    try std.testing.expectEqualStrings("outside", elems[1].toStringObject().str);
    try std.testing.expectEqualStrings("inside", elems[2].toStringObject().str);
    try std.testing.expectEqualStrings("outside", elems[3].toStringObject().str);
}

test "Fiber.alive? reflects fiber lifecycle" {
    const result = try evalCode(
        \\f = Fiber.new { Fiber.yield }
        \\a1 = f.alive?
        \\f.resume
        \\a2 = f.alive?
        \\f.resume
        \\a3 = f.alive?
        \\[a1, a2, a3]
    );
    try std.testing.expect(result.isArray());
    const elems = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 3), elems.len);
    try std.testing.expectEqual(true, elems[0].toBool());
    try std.testing.expectEqual(true, elems[1].toBool());
    try std.testing.expectEqual(false, elems[2].toBool());
}

test "Fiber.yield from main fiber raises FiberError" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput("Fiber.yield", &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "can't yield from root fiber (FiberError)") != null);
}

test "Fiber terminates after unhandled exception" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\f = Fiber.new { raise "boom" }
        \\begin
        \\  f.resume
        \\rescue => e
        \\  puts e.message
        \\end
        \\f.alive?
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.value.isBool());
    try std.testing.expectEqual(false, result.value.toBool());
    try std.testing.expectEqualSlices(u8, "boom\n", result.stdout);
}

test "Array#each + Fiber.yield resumes inside builtin" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\f = Fiber.new { [1,2].each { |x| Fiber.yield(x) }; :done }
        \\p f.resume
        \\p f.resume
        \\p f.resume
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("1\n2\n:done\n", result.stdout);
}

test "recursive comparisons are isolated between fibers" {
    const result = try evalCode(
        \\$calls = 0
        \\class FiberComparisonElement
        \\  def ==(other)
        \\    $calls += 1
        \\    Fiber.yield if $calls == 1
        \\    false
        \\  end
        \\end
        \\left = [FiberComparisonElement.new]
        \\right = [FiberComparisonElement.new]
        \\fiber = Fiber.new { left == right }
        \\fiber.resume
        \\outside = left == right
        \\inside = fiber.resume
        \\[outside, inside, $calls]
    );
    const elems = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 3), elems.len);
    try std.testing.expectEqual(false, elems[0].toBool());
    try std.testing.expectEqual(false, elems[1].toBool());
    try std.testing.expectEqual(@as(i64, 2), elems[2].toInteger());
}

test "Kernel#tap resumes and returns receiver" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\f = Fiber.new do
        \\  a = 1.tap { Fiber.yield(:pause) }
        \\  p a
        \\  :done
        \\end
        \\p f.resume
        \\p f.resume
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings(":pause\n1\n:done\n", result.stdout);
}

test "File.open block keeps io open across Fiber.yield" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\File.write('/tmp/cora_fiber_file_open_bug.txt', "hi")
        \\f = Fiber.new do
        \\  File.open('/tmp/cora_fiber_file_open_bug.txt', 'r') do |io|
        \\    Fiber.yield(:pause)
        \\    p io.read
        \\  end
        \\  :done
        \\end
        \\p f.resume
        \\p f.resume
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings(":pause\n\"hi\"\n:done\n", result.stdout);
}

test "Fiber works in non-main Thread" {
    const result = try evalCode(
        \\Thread.new do
        \\  f = Fiber.new do
        \\    Fiber.yield(:pause)
        \\    :done
        \\  end
        \\  [f.resume, f.resume]
        \\end.value
    );
    try std.testing.expect(result.isArray());
    const elems = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 2), elems.len);
    try std.testing.expect(elems[0].isSymbol());
    try std.testing.expectEqualStrings("pause", elems[0].toSymbolObject().name);
    try std.testing.expect(elems[1].isSymbol());
    try std.testing.expectEqualStrings("done", elems[1].toSymbolObject().name);
}

test "Thread.current stays correct inside Fiber in non-main Thread" {
    const result = try evalCode(
        \\Thread.new do
        \\  cur = Thread.current
        \\  Fiber.new { Thread.current == cur }.resume
        \\end.value
    );
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());
}

test "throw does not cross fiber boundary to outer catch" {
    const result = try evalCode(
        \\begin
        \\  catch(:done) do
        \\    Fiber.new { throw :done, 9 }.resume
        \\  end
        \\rescue UncaughtThrowError => e
        \\  [e.tag, e.value]
        \\end
    );
    try std.testing.expect(result.isArray());
    const elems = result.toArrayObject().elements.items;
    try std.testing.expect(elems[0].isSymbol());
    try std.testing.expectEqualStrings("done", elems[0].toSymbolObject().name);
    try std.testing.expectEqual(@as(i64, 9), elems[1].toInteger());
}

test "Fiber stress: 10000 yield/resume cycles" {
    const result = try evalCode(
        \\f = Fiber.new do
        \\  i = 0
        \\  while i < 10000
        \\    Fiber.yield(i)
        \\    i += 1
        \\  end
        \\  :done
        \\end
        \\i = 0
        \\ok = true
        \\while i < 10000
        \\  ok = false unless f.resume == i
        \\  i += 1
        \\end
        \\ok && f.resume == :done
    );
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());
}

test "Fiber stress: nested builtins with many yields" {
    const result = try evalCode(
        \\vals = []
        \\f = Fiber.new do
        \\  50.times do |i|
        \\    [i, i + 1].each do |x|
        \\      vals.tap { Fiber.yield(x) }
        \\    end
        \\  end
        \\  vals.length
        \\end
        \\sum = 0
        \\100.times { sum += f.resume }
        \\len = f.resume
        \\sum == 2500 && len == 0
    );
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());
}

test "Fiber transfer preserves native iteration and rescue state across GC" {
    const result = try evalCode(
        \\root = Fiber.current
        \\fiber = Fiber.new do
        \\  (1..100).map do |index|
        \\    begin
        \\      raise "child"
        \\    rescue => error
        \\      root.transfer(index)
        \\      [index, error.message, $!.message]
        \\    end
        \\  end
        \\end
        \\valid = true
        \\begin
        \\  raise "root"
        \\rescue
        \\  100.times do |index|
        \\    valid &&= fiber.transfer == index + 1
        \\    GC.start if index % 10 == 0
        \\    Thread.pass
        \\    valid &&= $!.message == "root"
        \\  end
        \\end
        \\values = fiber.transfer
        \\valid && !fiber.alive? && values == (1..100).map { |index| [index, "child", "child"] }
    );
    try std.testing.expect(result.isTruthy());
}

test "Fiber transfer remains in its owner thread during scheduler handoffs" {
    const result = try evalCode(
        \\workers = 2.times.map do
        \\  Thread.new do
        \\    owner = Thread.current
        \\    root = Fiber.current
        \\    child = Fiber.new do
        \\      100.times do
        \\        Thread.pass
        \\        root.transfer(Thread.current)
        \\      end
        \\      :done
        \\    end
        \\    valid = 100.times.all? { child.transfer.equal?(owner) }
        \\    valid && child.transfer == :done
        \\  end
        \\end
        \\workers.all? { |thread| thread.value }
    );
    try std.testing.expect(result.isTruthy());
}

test "Fiber raise replaces a pending return while suspended in ensure" {
    const result = try evalCode(
        \\root = Fiber.current
        \\events = []
        \\fiber = Fiber.new do
        \\  begin
        \\    lambda do
        \\      begin
        \\        return :old_return
        \\      ensure
        \\        root.transfer(:paused)
        \\        events << :unreachable
        \\      end
        \\    end.call
        \\  rescue => error
        \\    events << error.message
        \\    :rescued
        \\  ensure
        \\    events << :finished
        \\  end
        \\end
        \\paused = fiber.transfer
        \\GC.start
        \\result = fiber.raise("injected")
        \\paused == :paused && result == :rescued && events == ["injected", :finished] && !fiber.alive?
    );
    try std.testing.expect(result.isTruthy());
}

test "Fiber kill interrupts native iteration in a transferring fiber" {
    const result = try evalCode(
        \\root = Fiber.current
        \\events = []
        \\fiber = Fiber.new do
        \\  [1, 2].each do |index|
        \\    begin
        \\      root.transfer(index)
        \\    rescue Exception
        \\      events << :rescued
        \\    ensure
        \\      events << index
        \\    end
        \\  end
        \\  events << :continued
        \\end
        \\first = fiber.transfer
        \\GC.start
        \\killed = fiber.kill
        \\first == 1 && killed.equal?(fiber) && !fiber.alive? && events == [1]
    );
    try std.testing.expect(result.isTruthy());
}

test "Fiber kill remains pending after ensure yields" {
    const result = try evalCode(
        \\events = []
        \\fiber = Fiber.new do
        \\  begin
        \\    begin
        \\      Fiber.yield :body
        \\    ensure
        \\      Fiber.yield :cleanup
        \\      events << :unreachable
        \\    end
        \\  ensure
        \\    events << :outer_cleanup
        \\  end
        \\end
        \\first = fiber.resume
        \\killed = fiber.kill
        \\still_alive = fiber.alive?
        \\last = fiber.resume
        \\first == :body && killed.equal?(fiber) && still_alive && last.nil? &&
        \\  !fiber.alive? && events == [:outer_cleanup] && fiber.kill == false
    );
    try std.testing.expect(result.isTruthy());
}

test "Fiber storage snapshots isolate hashes while sharing values and defaults" {
    const result = try evalCode(
        \\class ContextStorage < Hash; end
        \\shared = []
        \\source = ContextStorage.new { |hash, key| hash[key] = [] }
        \\source[:shared] = shared
        \\fiber = Fiber.new(storage: source) do
        \\  snapshot = Fiber.current.storage
        \\  snapshot[:snapshot_only] = true
        \\  Fiber[:shared] << :child
        \\  Fiber[:generated] << :value
        \\  [Fiber.current.storage.class, Fiber.current.storage.keys.sort, Fiber[:generated]]
        \\end
        \\source[:later] = true
        \\values = fiber.resume
        \\values == [ContextStorage, [:generated, :shared], [:value]] &&
        \\  shared == [:child] && source.keys.sort == [:later, :shared]
    );
    try std.testing.expect(result.isTruthy());
}

test "Fiber storage setter and thread inheritance take separate snapshots" {
    const result = try evalCode(
        \\Fiber.new(storage: nil) do
        \\  source = {value: 1}
        \\  Fiber.current.storage = source
        \\  source[:value] = 2
        \\  thread = Thread.new do
        \\    before = Fiber[:value]
        \\    Fiber[:value] = 4
        \\    [before, Fiber[:value]]
        \\  end
        \\  Fiber[:value] = 3
        \\  thread.value == [1, 4] && Fiber[:value] == 3 && source[:value] == 2
        \\end.resume
    );
    try std.testing.expect(result.isTruthy());
}

test "Fiber blocking restores mode across suspension and injected exceptions" {
    const result = try evalCode(
        \\fiber = Fiber.new do
        \\  begin
        \\    Fiber.blocking do |current|
        \\      Fiber.yield [current.equal?(Fiber.current), current.blocking?, Fiber.blocking?]
        \\    end
        \\  rescue RuntimeError
        \\    [Fiber.current.blocking?, Fiber.blocking?]
        \\  end
        \\end
        \\inside = fiber.resume
        \\outside = [Fiber.current.blocking?, Fiber.blocking?]
        \\after = fiber.raise("interrupt")
        \\inside == [true, true, 1] && outside == [true, 1] && after == [false, false]
    );
    try std.testing.expect(result.isTruthy());
}

test "Fiber scheduler ownership and closing follow thread lifetime" {
    const result = try evalCode(
        \\events = []
        \\thread = Thread.new do
        \\  owner = Thread.current
        \\  scheduler = Object.new
        \\  [:block, :unblock, :kernel_sleep, :io_wait, :fiber_interrupt].each do |name|
        \\    scheduler.define_singleton_method(name) {}
        \\  end
        \\  scheduler.define_singleton_method(:scheduler_close) do
        \\    events << [Fiber.scheduler.equal?(scheduler), Thread.current.equal?(owner)]
        \\  end
        \\  scheduler.define_singleton_method(:close) { events << :wrong_hook }
        \\  Fiber.set_scheduler(scheduler)
        \\  :done
        \\end
        \\thread.value == :done && events == [[true, true]] && Fiber.scheduler.nil?
    );
    try std.testing.expect(result.isTruthy());
}

test "Fiber scheduler close errors preserve the exiting thread exception as cause" {
    const result = try evalCode(
        \\thread = Thread.new do
        \\  Thread.current.report_on_exception = false
        \\  scheduler = Object.new
        \\  [:block, :unblock, :kernel_sleep, :io_wait, :fiber_interrupt].each do |name|
        \\    scheduler.define_singleton_method(name) {}
        \\  end
        \\  scheduler.define_singleton_method(:scheduler_close) { raise "closing" }
        \\  Fiber.set_scheduler(scheduler)
        \\  raise "body"
        \\end
        \\begin
        \\  thread.value
        \\rescue => error
        \\  [error.message, error.cause.message, Fiber.scheduler.nil?]
        \\end == ["closing", "body", true]
    );
    try std.testing.expect(result.isTruthy());
}

test "Main fiber scheduler closes before at_exit handlers" {
    const result = try evalCode(
        \\events = []
        \\scheduler = Object.new
        \\[:block, :unblock, :kernel_sleep, :io_wait, :fiber_interrupt].each do |name|
        \\  scheduler.define_singleton_method(name) {}
        \\end
        \\scheduler.define_singleton_method(:close) { events << :closed }
        \\Fiber.set_scheduler(scheduler)
        \\at_exit { events << :at_exit }
        \\events
    );
    const entries = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 2), entries.len);
    try std.testing.expectEqualStrings("closed", entries[0].toSymbolObject().name);
    try std.testing.expectEqualStrings("at_exit", entries[1].toSymbolObject().name);
}

test "Fiber schedule forwards arguments keywords and block to scheduler" {
    const result = try evalCode(
        \\scheduler = Object.new
        \\[:block, :unblock, :kernel_sleep, :io_wait, :fiber_interrupt].each do |name|
        \\  scheduler.define_singleton_method(name) {}
        \\end
        \\scheduler.define_singleton_method(:fiber) do |positional, keyword:, &work|
        \\  Fiber.new(blocking: false) { work.call(positional, keyword) }.tap(&:resume)
        \\end
        \\Fiber.set_scheduler(scheduler)
        \\received = nil
        \\fiber = Fiber.schedule(:positional, keyword: :named) do |left, right|
        \\  received = [left, right, Fiber.current_scheduler.equal?(scheduler)]
        \\end
        \\Fiber.set_scheduler(nil)
        \\fiber.is_a?(Fiber) && received == [:positional, :named, true]
    );
    try std.testing.expect(result.isTruthy());
}
