module MonitorMixin
  class ConditionVariable
    # Releases the lock held in the associated monitor and waits;
    # reacquires the lock on wakeup.
    #
    # If +timeout+ is given, this method returns after +timeout+ seconds
    # passed, even if no other thread signaled.
    #
    def wait(timeout = nil)
      @monitor.mon_check_owner
      @monitor.wait_for_cond(@cond, timeout)
    end

    # Calls wait repeatedly while the given block yields a truthy value.
    #
    def wait_while
      while yield
        wait
      end
    end

    # Calls wait repeatedly until the given block yields a truthy value.
    #
    def wait_until
      until yield
        wait
      end
    end

    # Wakes up the first thread in line waiting for this lock.
    #
    def signal
      @monitor.mon_check_owner
      @cond.signal
    end

    # Wakes up all threads waiting for this lock.
    #
    def broadcast
      @monitor.mon_check_owner
      @cond.broadcast
    end

    private

    def initialize(monitor)
      @monitor = monitor
      @cond = Thread::ConditionVariable.new
    end
  end

  def self.extend_object(object)
    super
    object.__send__(:mon_initialize)
  end

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

  def mon_check_owner
    unless @mon_owner == Thread.current
      raise ThreadError, "current thread not owner"
    end
  end

  def wait_for_cond(cond, timeout)
    mon_check_owner
    count = @mon_count
    @mon_count = 0
    @mon_owner = nil
    begin
      cond.wait(@mon_mutex, timeout)
    ensure
      @mon_owner = Thread.current
      @mon_count = count
    end
  end

  def new_cond
    MonitorMixin::ConditionVariable.new(self)
  end

  def synchronize
    mon_enter
    begin
      yield
    ensure
      mon_exit
    end
  end

  private

  def initialize(*args, &block)
    super(*args, &block)
    mon_initialize
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

  def mon_check_owner
    unless @owner == Thread.current
      raise ThreadError, "current thread not owner"
    end
  end

  def wait_for_cond(cond, timeout)
    mon_check_owner
    count = @depth
    @depth = 0
    @owner = nil
    begin
      cond.wait(@mutex, timeout)
    ensure
      @owner = Thread.current
      @depth = count
    end
  end

  def new_cond
    MonitorMixin::ConditionVariable.new(self)
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
