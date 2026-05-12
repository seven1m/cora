# frozen_string_literal: true
# Stub for io/wait - provides non-blocking IO wait methods.
# Cora does not support non-blocking sockets, so these are minimal stubs
# sufficient for loading libraries that require io/wait (e.g. net/protocol).

class IO
  READABLE = 0x001 unless const_defined?(:READABLE)
  WRITABLE = 0x004 unless const_defined?(:WRITABLE)
  PRIORITY = 0x002 unless const_defined?(:PRIORITY)

  def wait_readable(timeout = nil)
    self
  end

  def wait_writable(timeout = nil)
    self
  end

  def wait(events, timeout = nil)
    events
  end

  def ready?
    true
  end
end

module IO::WaitReadable
end

module IO::WaitWritable
end

class IO::EAGAINWaitReadable < Errno::EAGAIN
  include IO::WaitReadable
end

class IO::EAGAINWaitWritable < Errno::EAGAIN
  include IO::WaitWritable
end

IO::EWOULDBLOCKWaitReadable = IO::EAGAINWaitReadable unless IO.const_defined?(:EWOULDBLOCKWaitReadable)
IO::EWOULDBLOCKWaitWritable = IO::EAGAINWaitWritable unless IO.const_defined?(:EWOULDBLOCKWaitWritable)

class IO::EINPROGRESSWaitReadable < Errno::EINPROGRESS
  include IO::WaitReadable
end
class IO::EINPROGRESSWaitWritable < Errno::EINPROGRESS
  include IO::WaitWritable
end
