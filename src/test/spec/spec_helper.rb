$__failures = []
$__passes = 0
$__describe = ""

def describe(desc)
  $__describe = desc
  yield
end

def it(desc)
  begin
    yield
    $__passes = $__passes + 1
  rescue
    $__failures << [$__describe, desc]
  end
end

class SpecExpectation
  def initialize(actual)
    @actual = actual
  end

  def ==(expected)
    if @actual != expected
      raise "mismatch"
    end
  end
end

class Object
  def should
    SpecExpectation.new(self)
  end
end

def report_results
  if $__failures.length > 0
    puts "FAILURES:"
    puts $__failures.length.to_s + " failed"
    puts "FAILED"
  else
    puts "OK: " + $__passes.to_s + " passed"
  end
end
