const std = @import("std");

test "start WEBrick server, make request, shut down" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{
            "zig-out/bin/cora",
            "-e",
            \\require "socket"
            \\require "webrick"
            \\
            \\server = WEBrick::HTTPServer.new(
            \\  Port: 0,
            \\  Logger: WEBrick::Log.new($stderr, WEBrick::BasicLog::FATAL),
            \\  AccessLog: [],
            \\)
            \\port = server.config[:Port]
            \\
            \\server.mount_proc "/hello" do |req, res|
            \\  res.body = "Hello from WEBrick!"
            \\end
            \\
            \\trap("TERM") { server.shutdown }
            \\
            \\parent_pid = Process.pid
            \\pid = Process.fork
            \\if pid == nil
            \\  sleep 0.3
            \\  sock = TCPSocket.new("127.0.0.1", port)
            \\  sock.write("GET /hello HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n")
            \\  result = sock.read
            \\  sock.close
            \\  if result.include?("Hello from WEBrick!")
            \\    puts "PASS"
            \\  else
            \\    puts "FAIL"
            \\  end
            \\  Process.kill("TERM", parent_pid)
            \\  exit(0)
            \\end
            \\
            \\server.start
            \\Process.wait(pid)
            ,
        },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualSlices(u8, "PASS\n", result.stdout);
}
