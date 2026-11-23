const std = @import("std");
const cora = @import("cora");
const bdwgc = @import("bdwgc");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Execution buffers allocate on first use and detach after completion" {
    bdwgc.init();
    defer bdwgc.deinit();
    const allocator = std.testing.allocator;
    var parser = try cora.prism.Parser.init(allocator,
        \\cold = Fiber.new { :unused }
        \\suspended = Fiber.new do
        \\  payload = ["kept"]
        \\  Fiber.yield -> { payload }
        \\  payload
        \\end
        \\capture = suspended.resume
        \\finished = Fiber.new { -> { ["done"] } }
        \\answer = finished.resume
        \\failed = Fiber.new { raise "expected" }
        \\begin failed.resume; rescue RuntimeError; end
        \\worker = Thread.new { Thread.stop }
        \\Thread.pass until worker.stop?
        \\GC.start
        \\raise "lost captures" unless capture.call == ["kept"] && answer.call == ["done"]
        \\[cold, suspended, finished, failed, worker]
    , null);
    defer parser.deinit();
    var program = try cora.compiler.Compiler.compile(allocator, &parser, 1);
    defer program.deinit();
    var vm = cora.vm.VM.initEmpty(allocator, cora.gc_allocator.scanned, cora.gc_allocator.atomic, std.testing.io, std.testing.environ);
    defer vm.deinit();
    try std.testing.expect(vm.current_thread == null);
    try vm.prepare(&program);
    try std.testing.expect(vm.main_thread != null and vm.current_thread == vm.main_thread);
    const objects = (try vm.run()).toArrayObject().elements.items;
    const cold = objects[0].toFiberObject();
    try std.testing.expectEqual(@as(usize, 0), cold.stack.storage.len);
    try std.testing.expectEqual(@as(usize, 0), cold.frames.storage.len);
    const suspended = objects[1].toFiberObject();
    try std.testing.expect(suspended.stack.storage.len > 0);
    try std.testing.expect(suspended.frames.storage.len > 0);
    for (objects[2..4]) |object| {
        const fiber = object.toFiberObject();
        try std.testing.expectEqual(@as(usize, 0), fiber.stack.storage.len);
        try std.testing.expectEqual(@as(usize, 0), fiber.frames.storage.len);
    }
    const worker = objects[4].toThreadObject();
    try std.testing.expect(worker.stack.storage.len > 0);
    try std.testing.expect(worker.frames.storage.len > 0);
    try std.testing.expectEqual(@as(usize, 0), worker.main_fiber.stack.storage.len);
    try std.testing.expectEqual(@as(usize, 0), worker.main_fiber.frames.storage.len);
    // The main thread likewise uses its main fiber's buffers, not a second pair.
    try std.testing.expectEqual(@as(usize, 0), vm.main_thread.?.stack.storage.len);
    try std.testing.expectEqual(@as(usize, 0), vm.main_thread.?.frames.storage.len);
    const unstarted = try vm.newThreadUnstarted(vm.thread_class);
    try std.testing.expect(unstarted.current_fiber == unstarted.main_fiber);
    try std.testing.expectEqual(@as(usize, 0), unstarted.stack.storage.len);
    try std.testing.expectEqual(@as(usize, 0), unstarted.frames.storage.len);
    try std.testing.expectEqual(@as(usize, 0), unstarted.main_fiber.stack.storage.len);
    try std.testing.expectEqual(@as(usize, 0), unstarted.main_fiber.frames.storage.len);
}

test "Thread retirement releases scheduler roots and suspended coroutine stacks" {
    bdwgc.init();
    defer bdwgc.deinit();
    const allocator = std.testing.allocator;
    var parser = try cora.prism.Parser.init(allocator,
        \\workers = Array.new(24) do
        \\  Thread.new do
        \\    fiber = Fiber.new { Fiber.yield; :unreachable }
        \\    fiber.resume
        \\    fiber
        \\  end
        \\end
        \\fibers = workers.map(&:value)
        \\GC.start
        \\fibers.all?(&:alive?) && workers.all? { |worker| worker.status == false } && Thread.list == [Thread.main]
    , null);
    defer parser.deinit();
    var program = try cora.compiler.Compiler.compile(allocator, &parser, 1);
    defer program.deinit();
    var vm = cora.vm.VM.initEmpty(allocator, cora.gc_allocator.scanned, cora.gc_allocator.atomic, std.testing.io, std.testing.environ);
    defer vm.deinit();
    try vm.prepare(&program);
    try std.testing.expect((try vm.run()).isTrue());
    try std.testing.expectEqual(@as(usize, 1), vm.thread_list.items.len);
    try std.testing.expectEqual(@as(usize, 0), vm.runnable_queue.items.len);
    try std.testing.expectEqual(@as(usize, 0), vm.zio_coroutines.items.len);
    try std.testing.expectEqual(@as(u32, 1), vm.thread_active_catches.count());
    try std.testing.expectEqual(@as(u32, 1), vm.thread_ensure_saved_unwinds.count());
    try std.testing.expectEqual(@as(u32, 1), vm.thread_rescued_exceptions.count());
    // Removed GC-owned list slots must not retain pointers outside items.len.
    for (vm.thread_list.unusedCapacitySlice()) |*slot| {
        for (std.mem.asBytes(slot)) |byte| try std.testing.expectEqual(@as(u8, 0), byte);
    }
    for (vm.runnable_queue.unusedCapacitySlice()) |*slot| {
        for (std.mem.asBytes(slot)) |byte| try std.testing.expectEqual(@as(u8, 0), byte);
    }
}

test "Thread retirement preserves retained values bindings locals and group" {
    const result = try evalCode(
        \\group = ThreadGroup.new
        \\worker = Thread.new do
        \\  Thread.current.name = "retained"
        \\  Thread.current[:fiber_key] = :fiber_value
        \\  Thread.current.thread_variable_set(:thread_key, :thread_value)
        \\  payload = ["escaped"]
        \\  [-> { payload }, binding, Fiber.current]
        \\end
        \\group.add(worker)
        \\answer = worker.value
        \\20.times { Thread.new {}.join }
        \\GC.start
        \\worker.join.equal?(worker) && worker.value.equal?(answer) &&
        \\  answer[0].call.equal?(answer[1].local_variable_get(:payload)) &&
        \\  answer[0].call == ["escaped"] && !answer[2].alive? &&
        \\  worker[:fiber_key] == :fiber_value && worker.thread_variable_get(:thread_key) == :thread_value &&
        \\  worker.name == "retained" && worker.group.equal?(group) && group.list.empty? &&
        \\  worker.status == false && worker.backtrace.nil?
    );
    try std.testing.expect(result.isTrue());
}

test "Thread diagnostics retain the original failure across yielding stderr callbacks and GC" {
    const result = try evalCode(
        \\class YieldingThreadDiagnostics
        \\  attr_reader :started, :buffer
        \\  def initialize
        \\    @buffer = ''
        \\  end
        \\  def write(message)
        \\    @started = true
        \\    Thread.pass
        \\    GC.start
        \\    @buffer << message
        \\  end
        \\  def flush; end
        \\end
        \\saved_stderr = $stderr
        \\writer = YieldingThreadDiagnostics.new
        \\begin
        \\  $stderr = writer
        \\  Thread.report_on_exception = false
        \\  original = RuntimeError.new('original failure')
        \\  worker = Thread.new do
        \\    Thread.current.report_on_exception = true
        \\    raise original
        \\  end
        \\  Thread.pass until writer.started
        \\  worker.kill
        \\  worker.raise 'late failure'
        \\  caught = begin worker.join; rescue RuntimeError => error; error; end
        \\  quiet = Thread.new { raise 'quiet failure' }
        \\  begin quiet.join; rescue RuntimeError; end
        \\  caught.equal?(original) && writer.buffer.include?('original failure') &&
        \\    !writer.buffer.include?('late failure') && !writer.buffer.include?('quiet failure') &&
        \\    !quiet.report_on_exception && Thread.main.report_on_exception
        \\ensure
        \\  $stderr = saved_stderr
        \\  Thread.report_on_exception = true
        \\end
    );
    try std.testing.expect(result.isTrue());
}

test "Thread descriptions preserve subclass identity and frozen name encodings after retirement" {
    const result = try evalCode(
        \\class EncodedWorker < Thread; end
        \\worker = EncodedWorker.new {}.join
        \\source = '名前'.encode('EUC-JP')
        \\worker.name = source
        \\source.replace('changed')
        \\GC.start
        \\stored = worker.name
        \\description = worker.to_s
        \\encoded = stored.frozen? && stored.encoding == Encoding::EUC_JP &&
        \\  stored.encode('UTF-8') == '名前' && description.encoding == Encoding::EUC_JP &&
        \\  description.encode('UTF-8').start_with?('#<EncodedWorker:') && description.include?(stored)
        \\worker.name = 'ascii'
        \\encoded && worker.to_s.encoding == Encoding::BINARY
    );
    try std.testing.expect(result.isTrue());
}

test "Thread retirement preserves exceptions and cross-thread fiber errors" {
    const result = try evalCode(
        \\worker = Thread.new { raise "retained failure" }
        \\worker.report_on_exception = false
        \\original = begin worker.join; rescue RuntimeError => error; error; end
        \\GC.start
        \\again = begin worker.value; rescue RuntimeError => error; error; end
        \\holder = Thread.new { fiber = Fiber.new { Fiber.yield }; fiber.resume; fiber }
        \\fiber = holder.value
        \\GC.start
        \\cross_thread = begin fiber.resume; rescue FiberError => error; error.message; end
        \\original.equal?(again) && again.message == "retained failure" &&
        \\  !again.backtrace.empty? && worker.status.nil? && fiber.alive? &&
        \\  cross_thread == "fiber called across threads"
    );
    try std.testing.expect(result.isTrue());
}

test "Thread.new creates and runs a thread" {
    const result = try evalCode(
        \\t = Thread.new { 42 }
        \\t.value
    );
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
}

test "Thread workers create child threads without recursively scheduling ancestors" {
    const result = try evalCode(
        \\ready = false
        \\workers = 2.times.map do
        \\  Thread.new do
        \\    Thread.pass until ready
        \\    Thread.new { Thread.pass; 42 }.value
        \\  end
        \\end
        \\ready = true
        \\workers.map(&:value) == [42, 42]
    );
    try std.testing.expect(result.isTruthy());
}

test "Thread scheduling preempts a busy main thread" {
    const result = try evalCode(
        \\done = false
        \\worker = Thread.new { done = true }
        \\while !done
        \\end
        \\worker.join
        \\done
    );
    try std.testing.expect(result.isTruthy());
}

test "Thread kill allows an ensure handler to yield before termination" {
    const result = try evalCode(
        \\started = false
        \\ensured = false
        \\worker = Thread.new do
        \\  begin
        \\    started = true
        \\    Thread.stop
        \\  ensure
        \\    Thread.pass
        \\    ensured = true
        \\  end
        \\end
        \\Thread.pass until started
        \\worker.kill.join
        \\ensured && !worker.alive?
    );
    try std.testing.expect(result.isTruthy());
}

test "Thread handoffs preserve nested fibers and main thread locals" {
    const result = try evalCode(
        \\main = Thread.current
        \\main[:marker] = :root
        \\worker = Thread.new do
        \\  Fiber.new do
        \\    Thread.current[:marker] = :worker_fiber
        \\    Thread.pass
        \\    Thread.current[:marker]
        \\  end.resume
        \\end
        \\answer = Fiber.new do
        \\  Thread.current[:marker] = :main_fiber
        \\  Fiber.new do
        \\    Thread.pass
        \\    GC.start
        \\    [Thread.current.equal?(main), worker.value]
        \\  end.resume + [Thread.current[:marker]]
        \\end.resume
        \\answer == [true, :worker_fiber, :main_fiber] && main[:marker] == :root
    );
    try std.testing.expect(result.isTruthy());
}

test "ObjectSpace registers finalizers for large Thread objects" {
    const result = try evalCode(
        \\thread = Thread.new { 42 }
        \\callback = proc { |_id| }
        \\registration = ObjectSpace.define_finalizer(thread, callback)
        \\[registration[0] == 0, registration[1].equal?(callback), ObjectSpace.undefine_finalizer(thread).equal?(thread), thread.value == 42]
    );
    const items = result.toArrayObject().elements.items;
    for (items) |item| try std.testing.expect(item.isTruthy());
}

test "Thread interrupt masks preserve FIFO order and are inherited by child threads" {
    const result = try evalCode(
        \\log = []
        \\Thread.handle_interrupt(Object => :never) do
        \\  worker = Thread.new do
        \\    Thread.current.raise 'first'
        \\    Thread.current.raise 'second'
        \\    log << Thread.pending_interrupt?(RuntimeError)
        \\    log << Thread.pending_interrupt?(ArgumentError)
        \\    2.times do
        \\      begin
        \\        Thread.handle_interrupt(RuntimeError => :immediate) { log << :unreachable }
        \\      rescue RuntimeError => error
        \\        log << error.message
        \\      end
        \\    end
        \\    log << Thread.pending_interrupt?
        \\  end
        \\  worker.join
        \\end
        \\log == [true, false, 'first', 'second', false]
    );
    try std.testing.expect(result.isTruthy());
}

test "Thread on_blocking interrupts distinguish Thread.pass from zero-duration sleep" {
    const result = try evalCode(
        \\log = []
        \\begin
        \\  Thread.handle_interrupt(RuntimeError => :on_blocking) do
        \\    Thread.current.raise 'blocking'
        \\    Thread.pass
        \\    log << :after_pass
        \\    sleep 0
        \\    log << :unreachable
        \\  end
        \\rescue RuntimeError => error
        \\  log << error.message
        \\end
        \\log == [:after_pass, 'blocking']
    );
    try std.testing.expect(result.isTruthy());
}

test "Thread masks defer external kill but self-kill remains immediate" {
    const result = try evalCode(
        \\log = []
        \\ready = Queue.new
        \\release = Queue.new
        \\worker = Thread.new do
        \\  begin
        \\    Thread.handle_interrupt(Object => :never) do
        \\      ready << true
        \\      release.pop
        \\      log << :completed_mask
        \\    end
        \\    log << :unreachable
        \\  ensure
        \\    log << :ensured
        \\  end
        \\end
        \\ready.pop
        \\worker.kill
        \\pending = worker.pending_interrupt?
        \\release << true
        \\worker.join
        \\Thread.new do
        \\  Thread.handle_interrupt(Object => :never) do
        \\    Thread.current.kill
        \\    log << :unreachable_self
        \\  end
        \\end.join
        \\pending && log == [:completed_mask, :ensured]
    );
    try std.testing.expect(result.isTruthy());
}

test "Thread scheduler join callbacks survive preemption and preserve worker exceptions" {
    const result = try evalCode(
        \\class JoinScheduler
        \\  attr_reader :events
        \\  def initialize
        \\    @events = []
        \\  end
        \\  def block(*args)
        \\    Fiber.yield
        \\  end
        \\  def unblock(*args)
        \\    @events << :entered
        \\    Thread.pass
        \\    GC.start
        \\    @events << :done
        \\  end
        \\  def kernel_sleep(*args); end
        \\  def io_wait(*args); end
        \\  def fiber_interrupt(*args); end
        \\end
        \\release = Queue.new
        \\worker = Thread.new do
        \\  Thread.current.report_on_exception = false
        \\  release.pop
        \\  raise 'worker failure'
        \\end
        \\scheduler = JoinScheduler.new
        \\Fiber.set_scheduler(scheduler)
        \\joiner = Fiber.new(blocking: false) do
        \\  begin
        \\    worker.value
        \\  rescue RuntimeError => error
        \\    error.message
        \\  end
        \\end
        \\joiner.resume
        \\release << true
        \\Thread.pass until scheduler.events.include?(:entered)
        \\GC.start
        \\Thread.pass until scheduler.events.include?(:done)
        \\answer = joiner.resume
        \\Fiber.set_scheduler(nil)
        \\timed = false
        \\begin
        \\  worker.join(0)
        \\rescue RuntimeError => error
        \\  timed = error.message == 'worker failure'
        \\end
        \\answer == 'worker failure' && timed && worker.status.nil?
    );
    try std.testing.expect(result.isTruthy());
}

test "Thread join and value park all waiters until their target exits" {
    const result = try evalCode(
        \\target = Thread.new { sleep 0.1; 42 }
        \\joiner = Thread.new { target.join(10).equal?(target) }
        \\reader = Thread.new { target.value }
        \\Thread.pass
        \\parked = joiner.status == "sleep" && reader.status == "sleep"
        \\parked && joiner.value && reader.value == 42
    );
    try std.testing.expect(result.isTruthy());
}

test "Thread#join timeout waits for elapsed time" {
    const result = try evalCode(
        \\thread = Thread.new { sleep 0.2 }
        \\start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        \\joined = thread.join(0.05)
        \\elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
        \\thread.kill.join
        \\joined.nil? && elapsed >= 0.04
    );
    try std.testing.expect(result.isTruthy());
}

test "Thread#value returns block result" {
    const result = try evalCode(
        \\t = Thread.new { 1 + 2 + 3 }
        \\t.value
    );
    try std.testing.expectEqual(@as(i64, 6), result.toInteger());
}

test "Thread clears non-local block return before next instruction" {
    const result = try evalCode(
        \\def passthrough
        \\  yield
        \\end
        \\
        \\class ThreadReturnDefaultDemo
        \\  def leaf(value)
        \\    value
        \\  end
        \\
        \\  def wrapper(size = 4096)
        \\    passthrough { return leaf(size) }
        \\  end
        \\
        \\  def run
        \\    [wrapper(2083), wrapper]
        \\  end
        \\end
        \\
        \\Thread.new { ThreadReturnDefaultDemo.new.run }.value
    );
    try std.testing.expect(result.isArray());
    const elems = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 2083), elems[0].toInteger());
    try std.testing.expectEqual(@as(i64, 4096), elems[1].toInteger());
}

test "Thread preserves a pending proc return across Thread.pass in ensure" {
    const result = try evalCode(
        \\Thread.new do
        \\  lambda do
        \\    callback = proc do
        \\      begin
        \\        return :done
        \\      ensure
        \\        Thread.pass
        \\      end
        \\    end
        \\    callback.call
        \\  end.call
        \\end.value
    );
    try std.testing.expect(result.isSymbol());
    try std.testing.expectEqualStrings("done", result.toSymbolObject().name);
}

test "Thread keeps rescued exceptions local across Thread.pass" {
    const result = try evalCode(
        \\thread = Thread.new do
        \\  begin
        \\    raise "inside"
        \\  rescue
        \\    Thread.pass
        \\    $!.message
        \\  end
        \\end
        \\begin
        \\  raise "outside"
        \\rescue
        \\  [thread.value, $!.message]
        \\end
    );
    try std.testing.expect(result.isArray());
    const elems = result.toArrayObject().elements.items;
    try std.testing.expectEqualStrings("inside", elems[0].toStringObject().str);
    try std.testing.expectEqualStrings("outside", elems[1].toStringObject().str);
}

test "Thread.current returns current thread" {
    const result = try evalCode(
        \\Thread.current == Thread.main
    );
    try std.testing.expectEqual(true, result.toBool());
}

test "Thread.main returns the main thread" {
    const result = try evalCode(
        \\Thread.main.alive?
    );
    try std.testing.expectEqual(true, result.toBool());
}

test "ThreadGroup default is available from Thread#group" {
    const result = try evalCode(
        \\g = Thread.current.group
        \\[ThreadGroup::Default == g, g.enclosed?, ThreadGroup::Default.add(Thread.current) == ThreadGroup::Default]
    );
    try std.testing.expect(result.isArray());
    const elems = result.toArrayObject().elements.items;
    try std.testing.expectEqual(true, elems[0].toBool());
    try std.testing.expectEqual(false, elems[1].toBool());
    try std.testing.expectEqual(true, elems[2].toBool());
}

test "ConditionVariable is available without requiring thread" {
    const result = try evalCode(
        \\[
        \\  defined?(ConditionVariable),
        \\  defined?(Thread::ConditionVariable),
        \\  ConditionVariable == Thread::ConditionVariable
        \\]
    );
    try std.testing.expect(result.isArray());
    const elems = result.toArrayObject().elements.items;
    try std.testing.expectEqualStrings("constant", elems[0].toStringObject().str);
    try std.testing.expectEqualStrings("constant", elems[1].toStringObject().str);
    try std.testing.expectEqual(true, elems[2].toBool());
}

test "ConditionVariable interrupted reacquisition preserves another thread's lock" {
    const result = try evalCode(
        \\mutex = Mutex.new
        \\cv = ConditionVariable.new
        \\ready = false
        \\owned_on_exit = false
        \\waiter = Thread.new do
        \\  mutex.synchronize do
        \\    ready = true
        \\    begin
        \\      cv.wait(mutex)
        \\    ensure
        \\      owned_on_exit = mutex.owned?
        \\    end
        \\  end
        \\end
        \\Thread.pass until ready && waiter.stop?
        \\mutex.lock
        \\cv.signal
        \\Thread.pass until waiter.stop?
        \\waiter.kill
        \\Thread.pass
        \\held_until_release = mutex.owned? && waiter.alive?
        \\mutex.unlock
        \\waiter.join
        \\held_until_release && owned_on_exit
    );
    try std.testing.expectEqual(true, result.toBool());
}

test "Thread#alive? returns true while running, false after termination" {
    const result = try evalCode(
        \\t = Thread.new { 42 }
        \\t.join
        \\t.alive?
    );
    try std.testing.expectEqual(false, result.toBool());
}

test "Thread backtraces use active fibers and the parked main stack" {
    const result = try evalCode(
        \\def trace_worker_fiber(main, traces)
        \\  traces << main.backtrace
        \\  traces << Thread.current.backtrace
        \\  Thread.stop
        \\end
        \\def inspect_main_trace(worker, traces)
        \\  Thread.pass until traces.size == 2 && worker.stop?
        \\  worker.backtrace
        \\end
        \\main = Thread.current
        \\traces = []
        \\worker = Thread.new { Fiber.new { trace_worker_fiber(main, traces) }.resume }
        \\parked = inspect_main_trace(worker, traces)
        \\worker.kill.join
        \\traces[0].any? { |line| line.include?('inspect_main_trace') } &&
        \\  traces[1].any? { |line| line.include?('trace_worker_fiber') } &&
        \\  parked.any? { |line| line.include?('trace_worker_fiber') } &&
        \\  worker.backtrace.nil?
    );
    try std.testing.expect(result.isTruthy());
}

test "Thread#status returns status strings" {
    const result = try evalCode(
        \\t = Thread.new { 42 }
        \\t.join
        \\t.status
    );
    // terminated normally => false
    try std.testing.expectEqual(false, result.toBool());
}

test "Thread.main status is 'run'" {
    const result = try evalCode(
        \\Thread.main.status
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualStrings("run", result.toStringObject().str);
}

test "Thread#[] and Thread#[]= store fiber-local variables" {
    const result = try evalCode(
        \\t = Thread.new {
        \\  Thread.current[:foo] = 42
        \\  Thread.current[:foo]
        \\}
        \\t.value
    );
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
}

test "Thread#key? checks for fiber-local variable" {
    const result = try evalCode(
        \\t = Thread.new {
        \\  Thread.current[:x] = 1
        \\  Thread.current.key?(:x)
        \\}
        \\t.value
    );
    try std.testing.expectEqual(true, result.toBool());
}

test "Thread#keys returns fiber-local variable keys" {
    const result = try evalCode(
        \\t = Thread.new {
        \\  Thread.current[:a] = 1
        \\  Thread.current.keys.length
        \\}
        \\t.value
    );
    try std.testing.expectEqual(@as(i64, 1), result.toInteger());
}

test "Thread#thread_variable_get/set" {
    const result = try evalCode(
        \\t = Thread.new {
        \\  Thread.current.thread_variable_set(:foo, 99)
        \\  Thread.current.thread_variable_get(:foo)
        \\}
        \\t.value
    );
    try std.testing.expectEqual(@as(i64, 99), result.toInteger());
}

test "Thread#thread_variable?" {
    const result = try evalCode(
        \\t = Thread.new {
        \\  Thread.current.thread_variable_set(:bar, 1)
        \\  Thread.current.thread_variable?(:bar)
        \\}
        \\t.value
    );
    try std.testing.expectEqual(true, result.toBool());
}

test "Thread#priority and Thread#priority=" {
    const result = try evalCode(
        \\t = Thread.new { 1 }
        \\t.priority = 2
        \\t.priority
    );
    try std.testing.expectEqual(@as(i64, 2), result.toInteger());
}

test "Thread abort_on_exception class and instance settings" {
    const result = try evalCode(
        \\original = Thread.abort_on_exception
        \\Thread.abort_on_exception = true
        \\thread = Thread.new { Thread.pass }
        \\thread.abort_on_exception = true
        \\values = [original, Thread.abort_on_exception, thread.abort_on_exception]
        \\thread.join
        \\Thread.abort_on_exception = original
        \\values
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expect(values[0].isFalse());
    try std.testing.expect(values[1].isTrue());
    try std.testing.expect(values[2].isTrue());
}

test "Thread.abort_on_exception propagates child exceptions to the main thread" {
    const result = try evalCode(
        \\original = Thread.abort_on_exception
        \\message = nil
        \\begin
        \\  Thread.abort_on_exception = true
        \\  Thread.new { raise "child failure" }
        \\  loop { Thread.pass }
        \\rescue RuntimeError => error
        \\  message = error.message
        \\ensure
        \\  Thread.abort_on_exception = original
        \\end
        \\message
    );
    try std.testing.expectEqualStrings("child failure", result.toStringObject().str);
}

test "Thread.list returns alive threads" {
    const result = try evalCode(
        \\Thread.list.length
    );
    // Main thread should always be in the list
    try std.testing.expect(result.toInteger() >= 1);
}

test "Thread.start is an alias for Thread.new" {
    const result = try evalCode(
        \\t = Thread.start { 7 }
        \\t.value
    );
    try std.testing.expectEqual(@as(i64, 7), result.toInteger());
}

test "Thread.fork starts a thread and returns its block result" {
    const result = try evalCode(
        \\t = Thread.fork { 8 }
        \\t.value
    );
    try std.testing.expectEqual(@as(i64, 8), result.toInteger());
}

test "Thread#stop? returns true for dead thread" {
    const result = try evalCode(
        \\t = Thread.new { 1 }
        \\t.join
        \\t.stop?
    );
    try std.testing.expectEqual(true, result.toBool());
}

test "Thread exception propagation through join" {
    const result = try evalCode(
        \\begin
        \\  t = Thread.new { raise "boom" }
        \\  t.join
        \\  "no error"
        \\rescue RuntimeError => e
        \\  e.message
        \\end
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualStrings("boom", result.toStringObject().str);
}

test "thread preemption lets tight loops make progress without Thread.pass" {
    const result = try evalCode(
        \\counter = 0
        \\t1 = Thread.new do
        \\  Thread.stop
        \\  while true
        \\    counter += 1
        \\  end
        \\end
        \\t2 = Thread.new do
        \\  t1.wakeup
        \\  while counter < 1
        \\    # Busy wait with no explicit yielding.
        \\  end
        \\  t1.kill
        \\  :done
        \\end
        \\t2.value
        \\t1.join
        \\counter >= 1
    );
    try std.testing.expectEqual(true, result.toBool());
}

test "throw does not cross thread boundary to outer catch" {
    const result = try evalCode(
        \\begin
        \\  catch(:done) do
        \\    Thread.new { throw :done, 11 }.value
        \\  end
        \\rescue UncaughtThrowError => e
        \\  [e.tag, e.value]
        \\end
    );
    try std.testing.expect(result.isArray());
    const elems = result.toArrayObject().elements.items;
    try std.testing.expect(elems[0].isSymbol());
    try std.testing.expectEqualStrings("done", elems[0].toSymbolObject().name);
    try std.testing.expectEqual(@as(i64, 11), elems[1].toInteger());
}

test "Thread.pass yields to other threads" {
    const result = try evalCode(
        \\Thread.pass
        \\42
    );
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
}

test "Thread#wakeup wakes a sleeping thread" {
    const result = try evalCode(
        \\t = Thread.new { 99 }
        \\t.join
        \\t.alive?
    );
    try std.testing.expectEqual(false, result.toBool());
}

test "Thread.pass works inside Fiber in non-main Thread" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{
            "zig-out/bin/cora",
            "-e",
            \\t = Thread.new do
            \\  f = Fiber.new do
            \\    Thread.pass
            \\    :ok
            \\  end
            \\  p f.resume
            \\end
            \\p t.value
            ,
        },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualSlices(u8, ":ok\n:ok\n", result.stdout);
}

test "Thread.start preserves positional and keyword arguments for its block" {
    const result = try evalCode(
        \\Thread.start(1, two: 2) { |first, second| [first, second] }.value == [1, {two: 2}]
    );
    try std.testing.expect(result.isTruthy());
}

test "Thread#fetch preserves coerced keys and current fiber storage" {
    const result = try evalCode(
        \\key = Object.new
        \\def key.to_str; "missing"; end
        \\thread = Thread.current
        \\begin
        \\  thread.fetch(key)
        \\rescue KeyError => e
        \\  raise "key metadata" unless e.key == "missing" && e.receiver.equal?(thread)
        \\end
        \\raise "coerced yield" unless thread.fetch(key) { |k| k } == "missing"
        \\thread[:slot] = :root
        \\inner = Fiber.new do
        \\  raise "root leaked" unless thread.fetch(:slot, :absent) == :absent
        \\  thread[:slot] = false
        \\  raise "false treated as missing" unless thread.fetch(:slot) { raise "yielded" } == false
        \\  thread[:slot] = nil
        \\  thread.fetch(:slot) { break :removed }
        \\end.resume
        \\raise "block break" unless inner == :removed
        \\thread.fetch(:slot) == :root
    );
    try std.testing.expect(result.isTruthy());
}

test "Thread native IDs follow the OS thread across coroutine handoffs" {
    const result = try evalCode(
        \\main_id = Thread.current.native_thread_id
        \\worker_id = Thread.new { Fiber.new { Thread.current.native_thread_id }.resume }.value
        \\[main_id, worker_id]
    );
    const ids = result.toArrayObject().elements.items;
    const expected: i64 = @intCast(std.Thread.getCurrentId());
    try std.testing.expectEqual(expected, ids[0].toInteger());
    try std.testing.expectEqual(expected, ids[1].toInteger());
}

test "Thread deadlocks raise fatal on main and allow cleanup" {
    const result = try evalCode(
        \\def deadlocked
        \\  begin
        \\    yield
        \\  rescue Exception => e
        \\    raise "wrong exception" unless e.class.name == "fatal" && !e.is_a?(StandardError)
        \\    raise "wrong message" unless e.message.include?("No live threads left. Deadlock?")
        \\    return true
        \\  end
        \\  raise "deadlock missed"
        \\end
        \\raise "queue" unless deadlocked { Queue.new.pop }
        \\cv, mutex = ConditionVariable.new, Mutex.new
        \\raise "condition" unless deadlocked { mutex.synchronize { cv.wait(mutex) } }
        \\q = Queue.new
        \\worker = Thread.new { q.pop }
        \\begin
        \\  raise "join" unless deadlocked { worker.join }
        \\ensure
        \\  q << :released
        \\  worker.join
        \\end
        \\left, right, ready = Mutex.new, Mutex.new, Queue.new
        \\left.lock
        \\worker = Thread.new do
        \\  right.lock
        \\  ready << true
        \\  begin
        \\    left.synchronize {}
        \\  ensure
        \\    right.unlock
        \\  end
        \\end
        \\ready.pop
        \\begin
        \\  raise "mutex" unless deadlocked { right.lock }
        \\ensure
        \\  left.unlock
        \\  worker.join
        \\end
        \\true
    );
    try std.testing.expect(result.isTruthy());
}

test "Thread.ignore_deadlock permits an external signal to release a queue" {
    const result = try evalCode(
        \\q = Queue.new
        \\original = Thread.ignore_deadlock
        \\previous = Signal.trap("USR1") { q << :signal }
        \\parent = Process.pid
        \\Thread.ignore_deadlock = true
        \\pid = Process.fork do
        \\  sleep 0.05
        \\  Process.kill("USR1", parent)
        \\  exit!
        \\end
        \\begin
        \\  q.pop == :signal
        \\ensure
        \\  Thread.ignore_deadlock = original
        \\  Signal.trap("USR1", previous)
        \\  Process.wait(pid)
        \\end
    );
    try std.testing.expect(result.isTruthy());
}

test "Enclosed ThreadGroups retain native membership across child creation and retirement" {
    const result = try evalCode(
        \\group = ThreadGroup.new
        \\ready, start, release = Queue.new, Queue.new, Queue.new
        \\worker = Thread.new do
        \\  ready << true
        \\  start.pop
        \\  child_release = Queue.new
        \\  child = Thread.new { child_release.pop }
        \\  ready << [Thread.current.group, child.group, child]
        \\  release.pop
        \\  child_release << true
        \\  child.join
        \\end
        \\ready.pop
        \\begin
        \\  group.add(worker)
        \\  raise "enclose return" unless group.enclose.equal?(group)
        \\  start << true
        \\  parent_group, child_group, child = ready.pop
        \\  GC.start
        \\  raise "inheritance" unless parent_group.equal?(group) && child_group.equal?(group)
        \\  raise "membership" unless group.list.include?(worker) && group.list.include?(child)
        \\  raise "hidden storage" unless group.instance_variables.empty? && worker.instance_variables.empty?
        \\  [group, ThreadGroup.new].each do |destination|
        \\    begin
        \\      destination.add(worker)
        \\      raise "enclosure ignored"
        \\    rescue ThreadError
        \\    end
        \\  end
        \\ensure
        \\  release << true
        \\  worker.join
        \\end
        \\raise "retirement" unless group.list.empty? && worker.group.equal?(group)
        \\ThreadGroup::Default.list.include?(Thread.main)
    );
    try std.testing.expect(result.isTruthy());
}

test "Queue scheduler waits clean up after spurious wakeups cancellation and timeouts" {
    const result = try evalCode(
        \\class QueueScheduler
        \\  attr_reader :blocks, :wakeups
        \\  def initialize
        \\    @blocks, @wakeups = [], []
        \\  end
        \\  def block(queue, timeout)
        \\    @blocks << [queue, Fiber.current, timeout]
        \\    Fiber.yield
        \\  end
        \\  def unblock(queue, fiber)
        \\    GC.start
        \\    @wakeups << [queue, fiber]
        \\  end
        \\  def kernel_sleep(*args); end
        \\  def io_wait(*args); end
        \\  def fiber_interrupt(*args); end
        \\end
        \\scheduler = QueueScheduler.new
        \\Fiber.set_scheduler(scheduler)
        \\q = Queue.new
        \\cancelled = Fiber.new(blocking: false) do
        \\  begin
        \\    q.pop
        \\  rescue RuntimeError => error
        \\    error.message
        \\  end
        \\end
        \\cancelled.resume
        \\cancelled.resume
        \\raise "spurious wake lost waiter" unless q.num_waiting == 1 && scheduler.blocks.size == 2
        \\raise "cancellation" unless cancelled.raise("cancelled") == "cancelled" && q.num_waiting == 0
        \\q << 1
        \\raise "stale waiter" unless scheduler.wakeups.empty? && q.pop == 1
        \\[Queue.new, SizedQueue.new(1)].each do |queue|
        \\  queue << 1 if queue.is_a?(SizedQueue)
        \\  timed = Fiber.new(blocking: false) do
        \\    queue.is_a?(SizedQueue) ? queue.push(2, timeout: 0.01) : queue.pop(timeout: 0.01)
        \\  end
        \\  timed.resume
        \\  timeout = scheduler.blocks.last.last
        \\  raise "timeout forwarding" unless timeout > 0 && timeout <= 0.01
        \\  sleep 0.02
        \\  raise "timeout cleanup" unless timed.resume.nil? && queue.num_waiting == 0
        \\end
        \\# Thread and fiber waits share FIFO order; wakeups use the captured scheduler,
        \\# including when the producer runs in another thread without a scheduler.
        \\thread = Thread.new { q.pop }
        \\Thread.pass until q.num_waiting == 1
        \\fiber = Fiber.new(blocking: false) { q.pop }
        \\fiber.resume
        \\q << 3
        \\raise "thread order" unless thread.value == 3 && scheduler.wakeups.empty?
        \\Thread.new { q << 4 }.join
        \\raise "scheduler ownership" unless scheduler.wakeups == [[q, fiber]]
        \\raise "fiber order" unless fiber.resume == 4 && q.num_waiting == 0
        \\Fiber.set_scheduler(nil)
        \\true
    );
    try std.testing.expect(result.isTruthy());
}

test "SizedQueue scheduler wake all preserves waits registered during callbacks" {
    const result = try evalCode(
        \\scheduler = Object.new
        \\scheduler.define_singleton_method(:block) { |queue, timeout| Fiber.yield }
        \\scheduler.define_singleton_method(:unblock) do |queue, fiber|
        \\  GC.start
        \\  fiber.resume
        \\end
        \\[:kernel_sleep, :io_wait, :fiber_interrupt].each do |name|
        \\  scheduler.define_singleton_method(name) {}
        \\end
        \\Fiber.set_scheduler(scheduler)
        \\q = SizedQueue.new(1)
        \\q << 0
        \\first = Fiber.new(blocking: false) { q << 1 }
        \\second = Fiber.new(blocking: false) { q << 2 }
        \\first.resume
        \\second.resume
        \\raise "wait count" unless q.num_waiting == 2
        \\q.clear
        \\raise "reentrant wake" unless !first.alive? && second.alive? && q.num_waiting == 1
        \\q.clear
        \\raise "new registration lost" unless !second.alive? && q.num_waiting == 0 && q.pop == 2
        \\# A larger capacity wakes every producer through the same callback path.
        \\q << 0
        \\third = Fiber.new(blocking: false) { q << 3 }
        \\fourth = Fiber.new(blocking: false) { q << 4 }
        \\third.resume
        \\fourth.resume
        \\q.max = 3
        \\raise "capacity wake" unless !third.alive? && !fourth.alive? && q.num_waiting == 0
        \\raise "items" unless [q.pop, q.pop, q.pop] == [0, 3, 4]
        \\Fiber.set_scheduler(nil)
        \\true
    );
    try std.testing.expect(result.isTruthy());
}

test "Queue native timeouts retain their deadline and registration after wakeup" {
    const result = try evalCode(
        \\[Queue.new, SizedQueue.new(1)].each do |q|
        \\  q << 1 if q.is_a?(SizedQueue)
        \\  worker = Thread.new do
        \\    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        \\    result = q.is_a?(SizedQueue) ? q.push(2, timeout: 0.05) : q.pop(timeout: 0.05)
        \\    [result, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started]
        \\  end
        \\  Thread.pass until q.num_waiting == 1
        \\  worker.wakeup
        \\  Thread.pass
        \\  raise "lost registration" unless q.num_waiting == 1 && worker.status == "sleep"
        \\  result, elapsed = worker.value
        \\  raise "elapsed timeout" unless result.nil? && elapsed >= 0.04 && q.num_waiting == 0
        \\end
        \\true
    );
    try std.testing.expect(result.isTruthy());
}
