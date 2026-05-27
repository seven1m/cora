# WEBrick Support

Missing features for basic WEBrick server use:

- [x] Socket.tcp_server_sockets
- [x] TCPServer.for_fd
- [x] IO.select used in main accept loop in /home/tim/pp/webrick/lib/webrick/server.rb:173. Covered by `spec/core/io/select_spec.rb`.
- [x] TCPServer#accept_nonblock used in /home/tim/pp/webrick/lib/webrick/server.rb:256. Covered by `spec/library/socket/tcpserver/accept_nonblock_spec.rb` and direct socket probe.
- [x] TCPSocket#do_not_reverse_lookup= used in /home/tim/pp/webrick/lib/webrick/server.rb:184. Covered by `spec/library/socket/basicsocket/do_not_reverse_lookup_spec.rb`.
- [x] TCPSocket#peeraddr used in /home/tim/pp/webrick/lib/webrick/server.rb:292. Verified with direct socket probe.
- [x] TCPServer#addr used in /home/tim/pp/webrick/lib/webrick/server.rb:113 and /home/tim/pp/webrick/lib/webrick/server.rb:361. Verified with direct socket probe and `WEBrick::HTTPServer.new(Port: 0, ...)`.
- [x] TCPServer#shutdown used in /home/tim/pp/webrick/lib/webrick/server.rb:365. Covered by `spec/library/socket/tcpserver/shutdown_spec.rb`.
- [x] ThreadGroup#list used in /home/tim/pp/webrick/lib/webrick/server.rb:210. `WEBrick::HTTPServer.new(DoNotListen: true).start` no longer dies here.

Secondary/optional gaps:

- [x] Socket.gethostname. Default `:ServerName` path in `/home/tim/pp/webrick/lib/webrick/config.rb` and `/home/tim/pp/webrick/lib/webrick/utils.rb` now works.
- [x] IO#autoclose=. Used in /home/tim/pp/webrick/lib/webrick/utils.rb:62.
- [x] Process.daemon. Covers `WEBrick::Daemon.start` in `/home/tim/pp/webrick/lib/webrick/server.rb:41` and upstream `spec/core/process/daemon_spec.rb`.
- [ ] Process.initgroups, Process::Sys.setuid/setgid missing. Still blocks priv-drop helper in `/home/tim/pp/webrick/lib/webrick/utils.rb:35`.
- [ ] `URI.parse("/")` still fails for WEBrick origin-form request targets. `WEBrick::HTTPRequest#parse_uri` in `/home/tim/pp/cora/ext/webrick/lib/webrick/httprequest.rb:527` calls `URI::parse(str)`, and normal requests like `GET / HTTP/1.0` still die at `/home/tim/pp/cora/ext/webrick/lib/webrick/httprequest.rb:233` with `bad URI '/'`.
- [x] `Time#httpdate` now works. Added `%a` (weekday name) and `%b` (month name) to strftime in `src/builtins/time.zig`.

Live probe status:

- Server boot and TCP accept work.
- Full HTTP response works with an absolute request-target like `GET http://127.0.0.1/ HTTP/1.0`
