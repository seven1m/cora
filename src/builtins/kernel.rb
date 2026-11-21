module Kernel
  def tap
    yield self
    self
  end
end
