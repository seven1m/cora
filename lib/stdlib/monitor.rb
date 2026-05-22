module MonitorMixin
  def mon_initialize
    @mon_mutex = Thread::Mutex.new
    @mon_owner = nil
    @mon_count = 0
  end

  def mon_enter
    if @mon_owner != Thread.current
      @mon_mutex.lock
      @mon_owner = Thread.current
    end
    @mon_count += 1
  end

  def mon_exit
    @mon_count -= 1
    if @mon_count == 0
      @mon_owner = nil
      @mon_mutex.unlock
    end
  end

  def synchronize
    mon_enter
    begin
      yield
    ensure
      mon_exit
    end
  end
end

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
