# Minimal forking static-file web server.
# Usage: cora examples/server.rb [port] [root]
#   port defaults to 3000; root defaults to the current working directory.

require 'socket'

PORT = (ARGV[0] || 3000).to_i
ROOT = ARGV[1] || Dir.pwd

CONTENT_TYPES = {
  'html' => 'text/html',
  'css'  => 'text/css',
  'js'   => 'text/javascript',
  'svg'  => 'image/svg+xml',
  'gif'  => 'image/gif',
  'png'  => 'image/png',
  'jpg'  => 'image/jpeg',
  'jpeg' => 'image/jpeg',
  'json' => 'application/json',
  'txt'  => 'text/plain',
}

server = TCPServer.new(PORT)
puts "serving #{ROOT} on http://localhost:#{PORT}"

pids = []
1.upto(4) do
  pids << fork do
    loop do
      client = server.accept
      line = client.gets
      if line.nil?
        client.close
        next
      end
      parts = line.split
      method = parts[0]
      target = parts[1]

      while (h = client.gets) && h != "\r\n"
      end

      target = '/index.html' if target == '/'
      path = ROOT + target

      if method == 'GET' && File.file?(path)
        ext = target.split('.').last
        ct  = CONTENT_TYPES.fetch(ext, 'application/octet-stream')
        body = File.read(path)
        client.write "HTTP/1.1 200\r\nContent-Type: #{ct}\r\nContent-Length: #{body.bytesize}\r\n\r\n"
        client.write body
        puts "#{method} #{target} 200"
      else
        client.write "HTTP/1.1 404\r\nContent-Length: 10\r\n\r\nnot found\n"
        puts "#{method} #{target} 404"
      end
      client.close
    end
  end
end

pids.each { |pid| Process.wait(pid) }
