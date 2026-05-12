# frozen_string_literal: true
# Stub for io/wait - provides non-blocking IO wait methods.
# Cora does not support non-blocking sockets, so these are minimal stubs
# sufficient for loading libraries that require io/wait (e.g. net/protocol).

class IO
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
