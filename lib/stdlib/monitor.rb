class Monitor
  def initialize
    @mutex = Thread::Mutex.new
    @owner = nil
    @depth = 0
  end

  def enter
    current = Thread.current
    if @owner == current
      @depth += 1
      return self
    end

    @mutex.lock
    @owner = current
    @depth = 1
    self
  end

  def exit
    raise ThreadError, "current thread not owner" unless @owner == Thread.current

    @depth -= 1
    return self unless @depth == 0

    @owner = nil
    @mutex.unlock
    self
  end

  def synchronize
    enter
    begin
      yield
    ensure
      exit
    end
  end
end
