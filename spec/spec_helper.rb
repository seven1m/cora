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

class BeAnInstanceOfMatcher
  def initialize(expected_class)
    @expected_class = expected_class
  end

  def matches?(actual)
    actual.instance_of?(@expected_class)
  end

  def failure_message(actual)
    "Expected #{actual.inspect} to be an instance of #{@expected_class}"
  end
end

def be_an_instance_of(expected_class)
  BeAnInstanceOfMatcher.new(expected_class)
end

class BooleanMatcher
  def initialize(expected)
    @expected = expected
  end

  def matches?(actual)
    actual == @expected
  end

  def failure_message(actual)
    "Expected #{actual.inspect} to be #{@expected.inspect}"
  end
end

def be_true
  BooleanMatcher.new(true)
end

def be_false
  BooleanMatcher.new(false)
end

class BeNilMatcher
  def matches?(actual)
    actual.nil?
  end

  def failure_message(actual)
    "Expected #{actual.inspect} to be nil"
  end
end

def be_nil
  BeNilMatcher.new
end

class RaiseErrorMatcher
  def initialize(expected_class = nil)
    @expected_class = expected_class
    @actual_exception = nil
  end

  def matches?(actual)
    unless actual.respond_to?(:call)
      return false
    end

    begin
      actual.call
      @actual_exception = nil
      false
    rescue => e
      @actual_exception = e
      return true if @expected_class.nil?
      e.is_a?(@expected_class)
    end
  end

  def failure_message(actual)
    unless actual.respond_to?(:call)
      return "Expected callable object, got #{actual.inspect}"
    end

    if @actual_exception.nil?
      if @expected_class.nil?
        "Expected block to raise an error, but no error was raised"
      else
        "Expected block to raise #{@expected_class}, but no error was raised"
      end
    else
      if @expected_class.nil?
        "Expected block to raise an error, got #{@actual_exception.class}: #{@actual_exception.message}"
      else
        "Expected block to raise #{@expected_class}, got #{@actual_exception.class}: #{@actual_exception.message}"
      end
    end
  end
end

def raise_error(expected_class = nil)
  RaiseErrorMatcher.new(expected_class)
end

class SpecMock
  def initialize(name = nil)
    @name = name || "mock"
    @forbidden_calls = {}
  end

  def should_not_receive(method_name)
    @forbidden_calls[method_name.to_sym] = true
    self
  end

  def method_missing(name, *args, &block)
    if @forbidden_calls[name.to_sym]
      raise SpecFailedException, "Expected #{@name} not to receive #{name}"
    end
    nil
  end

  def respond_to_missing?(_name, _include_private = false)
    true
  end
end

def mock(name = nil)
  SpecMock.new(name)
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
