require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Thread.list" do
  it "includes the current and main thread" do
    Thread.list.should include(Thread.current)
    Thread.list.should include(Thread.main)
  end

  it "includes threads of non-default thread groups" do
    CORAFIXME "ThreadGroup and sleeping thread behavior are not fully implemented in Cora" do
      t = Thread.new { sleep }
      begin
        ThreadGroup.new.add(t)
        Thread.list.should include(t)
      ensure
        t.kill
        t.join
      end
    end
  end

  it "does not include deceased threads" do
    CORAFIXME "Thread.list deceased-thread filtering is not fully implemented in Cora" do
      t = Thread.new { 1; }
      t.join
      Thread.list.should_not include(t)
    end
  end

  it "includes waiting threads" do
    CORAFIXME "Queue-backed waiting thread behavior is not fully implemented in Cora" do
      q = Queue.new
      t = Thread.new { q.pop }
      begin
        Thread.pass while t.status and t.status != 'sleep'
        Thread.list.should include(t)
      ensure
        q << nil
        t.join
      end
    end
  end

  it "returns instances of Thread and not null or nil values" do
    CORAFIXME "Thread.list iteration and thread spawning semantics are not fully implemented in Cora" do
      spawner = Thread.new do
        Array.new(100) do
          Thread.new {}
        end
      end

      begin
        Thread.list.each { |th|
          th.should be_kind_of(Thread)
        }
      end while spawner.alive?

      threads = spawner.value
      threads.each(&:join)
    end
  end
end
