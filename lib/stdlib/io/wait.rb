# frozen_string_literal: true
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
