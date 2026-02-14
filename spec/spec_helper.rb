$__failures = []
$__passes = 0
$__describe = ""
$__shared_examples = {}
$__skipped = []

def describe(desc, shared: false, &block)
  if shared
    $__shared_examples[desc] = block
    return
  end

  $__describe = desc
  block.call
end

def it_behaves_like(name, *args)
  shared = $__shared_examples[name]
  raise "Shared examples not found: #{name}" unless shared

  prev_method = @method
  @method = args[0] if args.length > 0
  $__describe = name
  shared.call
ensure
  @method = prev_method
end

def it(desc)
  begin
    yield
    $__passes = $__passes + 1
  rescue => e
    $__failures << [$__describe, desc, e.message]
  end
end

def xit(desc)
  $__skipped << [$__describe, desc]
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
      raise SpecFailedException, "Expected: #{expected.inspect}\nActual: #{@actual.inspect}"
    end
  end

  def match(matcher)
    if matcher.matches?(@actual)
      :noop
    else
      raise SpecFailedException, matcher.failure_message(@actual)
    end
  end

  def method_missing(name, *args, &block)
    result = @actual.send(name, *args, &block)
    if result
      :noop
    else
      raise SpecFailedException, "Expected #{@actual.inspect}.#{name} to be truthy"
    end
  end

  def respond_to_missing?(name, include_private = false)
    @actual.respond_to?(name, include_private) || super
  end
end

class SpecNegatedExpectation
  def initialize(actual)
    @actual = actual
  end

  def ==(expected)
    if @actual != expected
      :noop
    else
      raise SpecFailedException, "Expected value not to equal: #{expected.inspect}"
    end
  end

  def match(matcher)
    if matcher.matches?(@actual)
      raise SpecFailedException, "Expected value not to match: #{@actual.inspect}"
    else
      :noop
    end
  end

  def method_missing(name, *args, &block)
    result = @actual.send(name, *args, &block)
    if result
      raise SpecFailedException, "Expected #{@actual.inspect}.#{name} to be falsey"
    else
      :noop
    end
  end

  def respond_to_missing?(name, include_private = false)
    @actual.respond_to?(name, include_private) || super
  end
end

class EqualMatcher
  def initialize(expected)
    @expected = expected
  end

  def matches?(actual)
    actual.equal?(@expected)
  end

  def failure_message(actual)
    "Expected: #{@expected.inspect}\nActual: #{actual.inspect}"
  end
end

def equal(expected)
  EqualMatcher.new(expected)
end

class Object
  def should(*args)
    exp = SpecExpectation.new(self)
    return exp if args.length == 0
    matcher = args[0]
    begin
      exp.match(matcher)
    rescue NoMethodError
      exp.==(matcher)
    end
  end

  def should_not(*args)
    exp = SpecNegatedExpectation.new(self)
    return exp if args.length == 0
    matcher = args[0]
    begin
      exp.match(matcher)
    rescue NoMethodError
      exp.==(matcher)
    end
  end
end

def report_results
  if $__failures.length > 0
    puts "FAILURES (#{$__failures.length}):"
    puts
    $__failures.each do |details|
      puts "#{details[0]}: #{details[1]}"
      puts details[2]
    end
    if $__skipped.length > 0
      puts
      puts "SKIPPED (#{$__skipped.length}):"
      $__skipped.each do |details|
        puts "#{details[0]}: #{details[1]}"
      end
    end
  else
    puts "OK: #{$__passes} passed"
    if $__skipped.length > 0
      puts "SKIPPED: #{$__skipped.length}"
    end
  end
end

at_exit { report_results }
