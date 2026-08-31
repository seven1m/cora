const std = @import("std");
const builtin = @import("builtin");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

fn uniqueId() u64 {
    return @intCast(std.Io.Clock.boot.now(std.testing.io).nanoseconds);
}

fn createPathScript(allocator: std.mem.Allocator, stem: []const u8, body: []const u8) ![]u8 {
    const dir_path = try std.fmt.allocPrint(allocator, "/tmp/{s}-{d}", .{ stem, uniqueId() });
    errdefer allocator.free(dir_path);
    try std.Io.Dir.createDirAbsolute(std.testing.io, dir_path, .default_dir);
    errdefer std.Io.Dir.cwd().deleteTree(std.testing.io, dir_path) catch {};

    const script_path = try std.fmt.allocPrint(allocator, "{s}/cora-path-script", .{dir_path});
    errdefer allocator.free(script_path);

    const file = try std.Io.Dir.createFileAbsolute(std.testing.io, script_path, .{ .truncate = true });
    defer file.close(std.testing.io);
    try file.writeStreamingAll(std.testing.io, body);

    const script_path_z = try allocator.dupeZ(u8, script_path);
    defer allocator.free(script_path_z);
    if (std.c.chmod(script_path_z, 0o755) != 0) return error.PermissionDenied;

    allocator.free(script_path);
    return dir_path;
}

test "Process constant exists and is a module" {
    const result = try evalCode("Process.is_a?(Module)");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());
}

test "Process.uid returns current uid as Integer" {
    if (builtin.os.tag == .windows) {
        var stdout_buf: [1024]u8 = undefined;
        var stderr_buf: [1024]u8 = undefined;
        const bad = evalCodeWithOutput("Process.uid", &stdout_buf, &stderr_buf);
        try std.testing.expectEqual(error.UnhandledException, bad.err.?);
        try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "RuntimeError") != null);
        return;
    }

    const result = try evalCode("Process.uid");
    try std.testing.expect(result.isInteger());
    try std.testing.expect(result.toInteger() >= 0);
}

test "Process.euid returns current effective uid as Integer" {
    if (builtin.os.tag == .windows) {
        var stdout_buf: [1024]u8 = undefined;
        var stderr_buf: [1024]u8 = undefined;
        const bad = evalCodeWithOutput("Process.euid", &stdout_buf, &stderr_buf);
        try std.testing.expectEqual(error.UnhandledException, bad.err.?);
        try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "RuntimeError") != null);
        return;
    }

    const result = try evalCode("Process.euid");
    try std.testing.expect(result.isInteger());
    try std.testing.expect(result.toInteger() >= 0);
}

test "Process.clock_gettime returns float seconds by default" {
    if (builtin.os.tag == .windows) {
        var stdout_buf: [1024]u8 = undefined;
        var stderr_buf: [1024]u8 = undefined;
        const bad = evalCodeWithOutput("Process.clock_gettime(Process::CLOCK_MONOTONIC)", &stdout_buf, &stderr_buf);
        try std.testing.expectEqual(error.UnhandledException, bad.err.?);
        try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "RuntimeError") != null);
        return;
    }

    const result = try evalCode("Process.clock_gettime(Process::CLOCK_MONOTONIC)");
    try std.testing.expect(result.isFloat());
    try std.testing.expect(result.toFloatObject().val > 0);
}

test "Process.clock_gettime supports nanosecond unit" {
    if (builtin.os.tag == .windows) {
        var stdout_buf: [1024]u8 = undefined;
        var stderr_buf: [1024]u8 = undefined;
        const bad = evalCodeWithOutput("Process.clock_gettime(Process::CLOCK_REALTIME, :nanosecond)", &stdout_buf, &stderr_buf);
        try std.testing.expectEqual(error.UnhandledException, bad.err.?);
        try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "RuntimeError") != null);
        return;
    }

    const result = try evalCode("Process.clock_gettime(Process::CLOCK_REALTIME, :nanosecond)");
    try std.testing.expect(result.isInteger());
    try std.testing.expect(result.toInteger() > 0);
}

test "Process::WNOHANG exists" {
    const result = try evalCode("Process::WNOHANG");
    try std.testing.expect(result.isInteger());
    try std.testing.expect(result.toInteger() != 0);
}

test "Process.kill and Process.wait with WNOHANG work for popen child" {
    if (builtin.os.tag == .windows) {
        var stdout_buf: [1024]u8 = undefined;
        var stderr_buf: [1024]u8 = undefined;
        const bad = evalCodeWithOutput("Process.kill('TERM', 1)", &stdout_buf, &stderr_buf);
        try std.testing.expectEqual(error.UnhandledException, bad.err.?);
        try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "RuntimeError") != null);
        return;
    }

    const result = try evalCode(
        \\io = IO.popen(["/usr/bin/env", "sh", "-lc", "sleep 10"], err: [:child, :out])
        \\pid = io.pid
        \\first = Process.wait(pid, Process::WNOHANG)
        \\kill_count = Process.kill("KILL", pid)
        \\second = Process.wait(pid)
        \\status = $?
        \\io.close
        \\[
        \\  first.nil?,
        \\  kill_count,
        \\  second == pid,
        \\  status.signaled?,
        \\  status.termsig
        \\]
    );
    try std.testing.expect(result.isArray());
    const elems = result.toArrayObject().elements.items;
    try std.testing.expectEqual(true, elems[0].toBool());
    try std.testing.expectEqual(@as(i64, 1), elems[1].toInteger());
    try std.testing.expectEqual(true, elems[2].toBool());
    try std.testing.expectEqual(true, elems[3].toBool());
    try std.testing.expect(elems[4].toInteger() > 0);
}

test "Process::Status#pid returns pid after Process.wait" {
    if (builtin.os.tag == .windows) return;

    const result = try evalCode(
        \\io = IO.popen(["/usr/bin/env", "sh", "-lc", "true"], err: [:child, :out])
        \\pid = io.pid
        \\waited = Process.wait(pid)
        \\status_pid = $?.pid
        \\io.close
        \\[waited, status_pid]
    );
    try std.testing.expect(result.isArray());
    const elems = result.toArrayObject().elements.items;
    const pid = elems[0].toInteger();
    try std.testing.expect(pid > 0);
    try std.testing.expectEqual(pid, elems[1].toInteger());
}

test "Process.last_status returns the current thread's last process status" {
    if (builtin.os.tag == .windows) return;

    const result = try evalCode(
        \\before = Process.last_status
        \\pid = Process.spawn("/bin/sh", "-c", "exit 23")
        \\Process.wait(pid)
        \\[before, Process.last_status.equal?($?), Process.last_status.exitstatus]
    );
    try std.testing.expect(result.isArray());
    const elems = result.toArrayObject().elements.items;
    try std.testing.expect(elems[0].isNil());
    try std.testing.expectEqual(true, elems[1].toBool());
    try std.testing.expectEqual(@as(i64, 23), elems[2].toInteger());
}

test "Process.wait raises Interrupt instead of EINTR on SIGINT" {
    if (builtin.os.tag == .windows) return;

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{
            "build/bin/cora",
            "-e",
            "target = Process.spawn('/usr/bin/env', 'sh', '-lc', 'sleep 5'); sender = Process.spawn('/usr/bin/env', 'sh', '-lc', \"sleep 0.1; kill -INT #{Process.pid}\"); begin; Process.wait(target); rescue Interrupt; begin; Process.kill('KILL', target); rescue Exception; end; puts 'interrupt'; end",
        },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualStrings("interrupt\n", result.stdout);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "EINTR") == null);
}

test "Process.detach returns a Thread" {
    if (builtin.os.tag == .windows) return;

    const result = try evalCode(
        \\pid = Process.fork { exit(0) }
        \\thr = Process.detach(pid)
        \\thr.join
        \\thr.is_a?(Thread)
    );
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());
}

test "Process.detach thread value has correct pid" {
    if (builtin.os.tag == .windows) return;

    const result = try evalCode(
        \\pid = Process.fork { exit(0) }
        \\thr = Process.detach(pid)
        \\thr.join
        \\status = thr.value
        \\status.pid == pid
    );
    try std.testing.expectEqual(true, result.toBool());
}

test "Process.detach raises TypeError for non-integerable arg" {
    if (builtin.os.tag == .windows) return;

    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    const bad = evalCodeWithOutput(
        \\Process.detach(Object.new)
    , &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "TypeError") != null);
}

test "Process.spawn returns Integer pid" {
    if (builtin.os.tag == .windows) return;

    const result = try evalCode(
        \\pid = Process.spawn("true")
        \\pid.is_a?(Integer)
    );
    try std.testing.expectEqual(true, result.toBool());
}

test "IO.popen uses ENV PATH for executable lookup" {
    if (builtin.os.tag == .windows) return;

    const allocator = std.testing.allocator;
    const dir_path = try createPathScript(allocator, "cora-io-popen-path", "#!/bin/sh\necho io_path_ok\n");
    defer allocator.free(dir_path);
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, dir_path) catch {};

    const ruby_code = try std.fmt.allocPrint(
        allocator,
        \\old_path = ENV["PATH"]
        \\ENV["PATH"] = "{s}"
        \\io = IO.popen(["cora-path-script"], err: [:child, :out])
        \\pid = io.pid
        \\out = io.read
        \\Process.wait(pid)
        \\status = $?.exitstatus
        \\io.close
        \\ENV["PATH"] = old_path
        \\[out, status]
    ,
        .{dir_path},
    );
    defer allocator.free(ruby_code);

    const result = try evalCode(ruby_code);
    try std.testing.expect(result.isArray());
    const elems = result.toArrayObject().elements.items;
    try std.testing.expectEqualStrings("io_path_ok\n", elems[0].toStringObject().str);
    try std.testing.expectEqual(@as(i64, 0), elems[1].toInteger());
}

test "Process.spawn with array command runs process" {
    if (builtin.os.tag == .windows) return;

    const result = try evalCode(
        \\pid = Process.spawn("/bin/sh", "-c", "exit 42")
        \\thr = Process.detach(pid)
        \\thr.join
        \\thr.value.exitstatus
    );
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
}

test "Process.spawn uses ENV PATH for executable lookup" {
    if (builtin.os.tag == .windows) return;

    const allocator = std.testing.allocator;
    const dir_path = try createPathScript(allocator, "cora-process-spawn-path", "#!/bin/sh\necho process_path_ok\n");
    defer allocator.free(dir_path);
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, dir_path) catch {};

    const ruby_code = try std.fmt.allocPrint(
        allocator,
        \\r, w = IO.pipe
        \\old_path = ENV["PATH"]
        \\ENV["PATH"] = "{s}"
        \\pid = Process.spawn("cora-path-script", {{out: w}})
        \\w.close
        \\Process.wait(pid)
        \\out = r.read
        \\r.close
        \\ENV["PATH"] = old_path
        \\[out, $?.exitstatus]
    ,
        .{dir_path},
    );
    defer allocator.free(ruby_code);

    const result = try evalCode(ruby_code);
    try std.testing.expect(result.isArray());
    const elems = result.toArrayObject().elements.items;
    try std.testing.expectEqualStrings("process_path_ok\n", elems[0].toStringObject().str);
    try std.testing.expectEqual(@as(i64, 0), elems[1].toInteger());
}

test "Process.spawn with IO redirection works" {
    if (builtin.os.tag == .windows) return;

    const result = try evalCode(
        \\r, w = IO.pipe
        \\pid = Process.spawn("/bin/sh", "-c", "echo hello", {out: w})
        \\w.close
        \\thr = Process.detach(pid)
        \\thr.join
        \\r.read.strip
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "hello", result.toStringObject().str);
}

test "Process::Status#to_i returns raw wait status integer" {
    if (builtin.os.tag == .windows) return;

    const result = try evalCode(
        \\io = IO.popen(["/usr/bin/env", "sh", "-lc", "exit 42"], err: [:child, :out])
        \\pid = io.pid
        \\_ = Process.wait(pid)
        \\raw = $?.to_i
        \\io.close
        \\raw
    );
    try std.testing.expect(result.isInteger());
    // exit 42 -> raw_status = (42 & 0xff) << 8 = 10752
    try std.testing.expectEqual(@as(i64, 10752), result.toInteger());
}

test "nonblocking popen loop drains child output" {
    if (builtin.os.tag == .windows) return;

    const result = try evalCode(
        \\io = IO.popen(["/usr/bin/env", "sh", "-lc", "echo one; sleep 0.1; echo two"], err: [:child, :out])
        \\pid = io.pid
        \\buffer = +""
        \\lines = []
        \\child_done = false
        \\loop do
        \\  child_done = true if !child_done && Process.wait(pid, Process::WNOHANG) == pid
        \\  io.wait_readable(0.1)
        \\  loop do
        \\    available = io.nread
        \\    break if available.zero?
        \\    chunk_len = available < 4096 ? available : 4096
        \\    chunk = io.read(chunk_len)
        \\    break if chunk.nil? || chunk.empty?
        \\    buffer << chunk
        \\    while (newline_idx = buffer.index("\\n"))
        \\      lines << buffer.slice!(0, newline_idx + 1).strip
        \\    end
        \\  end
        \\  break if child_done && io.nread.zero?
        \\end
        \\lines << buffer unless buffer.empty?
        \\io.close
        \\lines.join("|")
    );
    try std.testing.expect(result.isString());
    try std.testing.expect(std.mem.indexOf(u8, result.toStringObject().str, "one") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.toStringObject().str, "two") != null);
}
