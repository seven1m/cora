# WEBrick Support

Missing features for basic WEBrick server use:

- [ ] Socket.tcp_server_sockets
- [ ] TCPServer.for_fd
- [ ] IO.select used in main accept loop in /home/tim/pp/webrick/lib/webrick/server.rb:173
- [ ] TCPServer#accept_nonblock used in /home/tim/pp/webrick/lib/webrick/server.rb:256
- [ ] TCPSocket#do_not_reverse_lookup= used in /home/tim/pp/webrick/lib/webrick/server.rb:184
- [ ] TCPSocket#peeraddr used in /home/tim/pp/webrick/lib/webrick/server.rb:292
- [ ] TCPServer#addr used in /home/tim/pp/webrick/lib/webrick/server.rb:113 and /home/tim/pp/webrick/lib/webrick/server.rb:361
- [ ] TCPServer#shutdown used in /home/tim/pp/webrick/lib/webrick/server.rb:365
- [x] ThreadGroup#list used in /home/tim/pp/webrick/lib/webrick/server.rb:210. `WEBrick::HTTPServer.new(DoNotListen: true).start` no longer dies here.

Secondary/optional gaps:

- [x] Socket.gethostname. Default `:ServerName` path in `/home/tim/pp/webrick/lib/webrick/config.rb` and `/home/tim/pp/webrick/lib/webrick/utils.rb` now works.
- [ ] IO#autoclose= missing. Used in /home/tim/pp/webrick/lib/webrick/utils.rb:62.
- [ ] Process.daemon, Process.initgroups, Process::Sys.setuid/setgid missing. Affects daemon/priv-drop helpers in /home/tim/pp/webrick/lib/webrick/server.rb:41 and /home/tim/pp/webrick/lib/webrick/utils.rb:35.
