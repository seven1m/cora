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
  rescue => e
    $__failures << [$__describe, desc, e.message]
  end
end

class SpecFailedException < StandardError; end

class SpecExpectation
  def initialize(actual)
    @actual = actual
  end

  def ==(expected)
    if @actual == expected
      :noop
    else
      raise SpecFailedException, "Expected: " + expected.inspect + "\nActual: " + @actual.inspect
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
    puts 'FAILURES (' + $__failures.length.to_s + '):'
    puts
    $__failures.each do |details|
      puts details[0] + ': ' + details[1]
      puts details[2]
    end
  else
    puts "OK: " + $__passes.to_s + " passed"
  end
end
