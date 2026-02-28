require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Thread.stop" do
  it "causes the current thread to sleep indefinitely" do
    t = Thread.new { Thread.stop; 5 }
    Thread.pass while t.status and t.status != 'sleep'
    t.status.should == 'sleep'
    t.run
    t.value.should == 5
  end
end

describe "Thread#stop?" do
  it "can check it's own status" do
    ThreadSpecs.status_of_current_thread.should_not.stop?
  end

  it "describes a running thread" do
    ThreadSpecs.status_of_running_thread.should_not.stop?
  end

  it "describes a sleeping thread" do
    CORAFIXME "Thread sleeping stop? semantics are not fully implemented in Cora" do
      ThreadSpecs.status_of_sleeping_thread.should.stop?
    end
  end

  it "describes a blocked thread" do
    CORAFIXME "Mutex/blocking stop? semantics are not fully implemented in Cora" do
      ThreadSpecs.status_of_blocked_thread.should.stop?
    end
  end

  it "describes a completed thread" do
    ThreadSpecs.status_of_completed_thread.should.stop?
  end

  it "describes a killed thread" do
    CORAFIXME "Thread kill/sleep stop? behavior differs in Cora" do
      ThreadSpecs.status_of_killed_thread.should.stop?
    end
  end

  it "describes a thread with an uncaught exception" do
    CORAFIXME "Thread exception/stop? semantics are not fully implemented in Cora" do
      ThreadSpecs.status_of_thread_with_uncaught_exception.should.stop?
    end
  end

  it "describes a dying running thread" do
    CORAFIXME "Thread dying-running stop? semantics are not fully implemented in Cora" do
      ThreadSpecs.status_of_dying_running_thread.should_not.stop?
    end
  end

  it "describes a dying sleeping thread" do
    CORAFIXME "Thread dying-sleeping stop? semantics are not fully implemented in Cora" do
      ThreadSpecs.status_of_dying_sleeping_thread.should.stop?
    end
  end

  it "describes a dying thread after sleep" do
    CORAFIXME "Thread dying-after-sleep stop? semantics are not fully implemented in Cora" do
      ThreadSpecs.status_of_dying_thread_after_sleep.should_not.stop?
    end
  end
end
