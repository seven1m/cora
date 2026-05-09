class ConditionVariable
  def initialize
    @waiters = []
  end

  def wait(mutex, timeout = nil)
    current = Thread.current
    @waiters << current
    mutex.unlock

    begin
      if timeout
        deadline = Time.now.to_f + timeout
        while @waiters.include?(current) && (deadline - Time.now.to_f) > 0
          Thread.pass
        end
      else
        Thread.pass while @waiters.include?(current)
      end
    ensure
      @waiters.delete(current)
      mutex.lock
    end

    self
  end

  def signal
    waiter = @waiters.shift
    waiter.run if waiter && waiter.alive?
    self
  end

  def broadcast
    waiters = @waiters
    @waiters = []
    waiters.each do |waiter|
      waiter.run if waiter.alive?
    end
    self
  end
end

Thread::ConditionVariable = ConditionVariable
