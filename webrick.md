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
- [ ] Process.daemon, Process.initgroups, Process::Sys.setuid/setgid missing. Affects daemon/priv-drop helpers in /home/tim/pp/webrick/lib/webrick/server.rb:41 and /home/tim/pp/webrick/lib/webrick/utils.rb:35.
