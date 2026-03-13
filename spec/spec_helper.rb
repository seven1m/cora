$__failures = []
$__passes = 0
$__examples_total = 0
$__shared_examples = {}
$__skipped = []
$__active_mocks = []
$__root_contexts = []
$__current_context = nil
$__spec_main = self

class SpecContextState
  attr_reader :description, :parent, :children, :examples, :entries

  def initialize(description, shared: false)
    @description = description.to_s
    @shared = shared
    @parent = nil
    @children = []
    @examples = []
    @entries = []
    @before = { all: [], each: [] }
    @after = { all: [], each: [] }
  end

  def shared?
    @shared
  end

  def parent=(parent)
    @parent = parent
  end

  def add_child(child)
    child.parent = self
    @children << child
    @entries << [:context, child]
  end

  def add_example(example)
    example.context = self
    @examples << example
    @entries << [:example, example]
  end

  def before(scope = :each, &block)
    return @before[scope] unless block
    @before[scope] << block
  end

  def after(scope = :each, &block)
    return @after[scope] unless block
    @after[scope] << block
  end

  def hooks(kind, scope)
    own = (kind == :before ? @before : @after)[scope]
    return own if @parent.nil?

    if kind == :before
      @parent.hooks(kind, scope) + own
    else
      reverse_blocks(own) + @parent.hooks(kind, scope)
    end
  end

  def full_description
    return @description if @parent.nil? || @parent.full_description == ""
    return @parent.full_description if @description == ""
    @parent.full_description + " " + @description
  end

  def include_shared(shared)
    shared.before(:all).each { |hook| before(:all, &hook) }
    shared.before(:each).each { |hook| before(:each, &hook) }
    shared.after(:each).each { |hook| after(:each, &hook) }
    shared.after(:all).each { |hook| after(:all, &hook) }

    shared.entries.each do |entry_kind, entry|
      case entry_kind
      when :example
        add_example(entry.dup)
      when :context
        add_child(entry.deep_dup)
      end
    end
  end

  def deep_dup
    copy = SpecContextState.new(@description, shared: false)
    @before[:all].each { |hook| copy.before(:all, &hook) }
    @before[:each].each { |hook| copy.before(:each, &hook) }
    @after[:each].each { |hook| copy.after(:each, &hook) }
    @after[:all].each { |hook| copy.after(:all, &hook) }

    @entries.each do |entry_kind, entry|
      case entry_kind
      when :example
        copy.add_example(entry.dup)
      when :context
        copy.add_child(entry.deep_dup)
      end
    end

    copy
  end

  private

  def reverse_blocks(list)
    out = []
    i = list.length - 1
    while i >= 0
      out << list[i]
      i -= 1
    end
    out
  end
end

class SpecExampleState
  attr_accessor :context
  attr_reader :description, :block

  def initialize(description, block, skipped: false)
    @description = description
    @block = block
    @skipped = skipped
    @context = nil
  end

  def skipped?
    @skipped
  end

  def dup
    SpecExampleState.new(@description, @block, skipped: @skipped)
  end
end

def current_context
  $__current_context
end

def record_failure(group_desc, it_desc, error)
  message = error.message
  if error.respond_to?(:class) && error.class
    message = "#{error.class}: #{message}"
  end
  $__failures << [group_desc, it_desc, message]
end

def run_spec_blocks(group_desc, label, blocks)
  blocks.each do |block|
    begin
      block.call
    rescue Exception => e
      record_failure(group_desc, label, e)
      return false
    end
  end
  true
end

def run_spec_example(example)
  $__examples_total = $__examples_total + 1
  group_desc = example.context.full_description
  if example.skipped?
    $__skipped << [group_desc, example.description]
    return
  end

  error = nil

  begin
    example.context.hooks(:before, :all).each { |hook| hook.call }
    example.context.hooks(:before, :each).each { |hook| hook.call }
    example.block.call
  rescue Exception => e
    error = e
  ensure
    begin
      $__active_mocks.each { |mock| mock.verify_expectations! }
    rescue Exception => e
      error = e if error.nil?
    end

    begin
      example.context.hooks(:after, :each).each { |hook| hook.call }
    rescue Exception => e
      error = e if error.nil?
    end

    $__active_mocks = []
  end

  if error
    record_failure(group_desc, example.description, error)
  else
    $__passes = $__passes + 1
  end
end

def run_spec_context(context)
  context.entries.each do |entry_kind, entry|
    case entry_kind
    when :example
      run_spec_example(entry)
    when :context
      run_spec_context(entry)
    end
  end

  run_spec_blocks(context.full_description, "after :all", context.after(:all))
end

def run_spec_suite
  $__root_contexts.each do |context|
    run_spec_context(context)
  end
end

def describe(desc, shared: false, &block)
  ctx = SpecContextState.new(desc, shared: shared)
  if shared
    previous = $__current_context
    $__current_context = ctx
    block.call if block
    $__shared_examples[desc.to_s] = ctx
    $__current_context = previous
    return
  end

  if $__current_context.nil?
    $__root_contexts << ctx
  else
    $__current_context.add_child(ctx)
  end

  previous = $__current_context
  $__current_context = ctx
  block.call if block
ensure
  $__current_context = previous
end

def context(desc, &block)
  describe(desc, &block)
end

def before(scope = :each, &block)
  current_context.before(scope, &block)
end

def after(scope = :each, &block)
  current_context.after(scope, &block)
end

def it_behaves_like(name, *args)
  meth = args[0]
  obj = args[1]
  before(:all) do
    @method = meth
    @object = obj
  end
  after(:all) do
    @method = nil
    @object = nil
  end
  it_should_behave_like(name)
end

def it_should_behave_like(name, *args)
  raise ArgumentError, "it_should_behave_like does not accept arguments" unless args.empty?
  shared = $__shared_examples[name.to_s]
  raise "Shared examples not found: #{name}" unless shared

  current_context.include_shared(shared)
end

def it(desc, &block)
  current_context.add_example(SpecExampleState.new(desc, block, skipped: block.nil?))
end

def xit(desc)
  current_context.add_example(SpecExampleState.new(desc, nil, skipped: true))
end

class ScratchPad
  @recorded = nil

  class << self
    def clear
      @recorded = nil
    end

    def record(value)
      @recorded = value
    end

    def <<(value)
      @recorded << value
    end

    def recorded
      @recorded
    end
  end
end

def parse_version_segments(version)
  version.to_s.split('.').map { |segment| segment.to_i }
end

def compare_versions(lhs, rhs)
  a = parse_version_segments(lhs)
  b = parse_version_segments(rhs)
  max_len = a.length
  max_len = b.length if b.length > max_len
  i = 0
  while i < max_len
    av = a[i] || 0
    bv = b[i] || 0
    return -1 if av < bv
    return 1 if av > bv
    i += 1
  end
  0
end

def ruby_version_is(*args, **_kwargs, &block)
  requirement = args[0]
  matches = false
  if requirement.is_a?(Range)
    begin_ver = requirement.begin
    end_ver = requirement.end
    lower_ok = begin_ver.nil? || begin_ver == "" || compare_versions(RUBY_VERSION, begin_ver) >= 0
    upper_cmp = compare_versions(RUBY_VERSION, end_ver)
    upper_ok = requirement.exclude_end? ? upper_cmp < 0 : upper_cmp <= 0
    matches = lower_ok && upper_ok
  else
    matches = requirement.nil? || compare_versions(RUBY_VERSION, requirement) >= 0
  end
  block.call if matches && block
  matches
end

def ruby_bug(_id, *args, **kwargs, &block)
  return unless block
  if args.empty?
    block.call
  else
    ruby_version_is(*args, **kwargs, &block)
  end
end

def fixture(spec_file, fixture_name)
  path = spec_file.to_s
  absolute = path.length > 0 && path[0] == "/"
  parts = path.split("/")
  base = ""
  i = 0
  limit = parts.length - 1
  while i < limit
    if base == ""
      base = parts[i]
    else
      base = "#{base}/#{parts[i]}"
    end
    i += 1
  end
  if base == ""
    base = absolute ? "/" : "."
  elsif absolute
    base = "/#{base}"
  end
  "#{base}/fixtures/#{fixture_name}"
end

def cora_bin_path
  "#{__dir__}/../zig-out/bin/cora"
end

def ruby_exe(script_path)
  `#{cora_bin_path} "#{script_path}"`
end

def c_long_size
  64
end

def pointer_size
  64
end

def max_long
  9223372036854775807
end

def min_long
  -9223372036854775808
end

def infinity_value
  1.0 / 0.0
end

def nan_value
  0.0 / 0.0
end

def bignum_value(offset = 0)
  value = 1
  c_long_size.times { value *= 2 }
  value + offset
end

def fixnum_max
  max_long
end

def platform_is(*_args, **kwargs, &block)
  requested_size = kwargs[:c_long_size]
  if !requested_size.nil? && requested_size != c_long_size
    return
  end
  requested_pointer_size = kwargs[:pointer_size]
  if !requested_pointer_size.nil? && requested_pointer_size != pointer_size
    return
  end
  block.call if block
end

def platform_is_not(*_args, **kwargs, &block)
  requested_size = kwargs[:c_long_size]
  if !requested_size.nil? && requested_size == c_long_size
    return
  end
  requested_pointer_size = kwargs[:pointer_size]
  if !requested_pointer_size.nil? && requested_pointer_size == pointer_size
    return
  end
  block.call if block
end

def little_endian(&block)
  block.call if [1].pack("S").unpack("C").first == 1
end

def big_endian(&block)
  block.call if [1].pack("S").unpack("C").first != 1
end

def not_supported_on(*_args, **_kwargs, &block)
  block.call if block
end

def deviates_on(*_args, **_kwargs, &block)
  block.call if block
end

def quarantine!(*_args); end

def guard(*_args, **_kwargs, &block)
  block.call if block
end

def guard_not(*_args, **_kwargs, &block)
  block.call if block
end

def flunk(message = "Flunked")
  raise SpecFailedException, message
end

class SpecFailedException < StandardError; end
class CoraFixMeException < StandardError; end

def CORAFIXME(description, exception: StandardError, message: nil, condition: true)
  raise SpecFailedException, "CORAFIXME requires a block" unless block_given?
  return yield unless condition

  matcher = case message
  when String
    ->(actual_message) { actual_message.include?(message) }
  when Regexp
    ->(actual_message) { !(actual_message =~ message).nil? }
  when nil
    ->(_actual_message) { true }
  else
    raise ArgumentError, "message must be nil, String, or Regexp"
  end

  status = nil
  captured = nil
  begin
    yield
    status = :unexpected_pass
  rescue exception => e
    captured = e
    if matcher.call(e.message)
      status = :valid_fixme
    else
      status = :wrong_message
    end
  rescue Exception => e
    captured = e
    status = :wrong_class
  end

  case status
  when :unexpected_pass
    raise CoraFixMeException, "Issue has been fixed, please remove or update CORAFIXME: #{description}"
  when :wrong_message
    raise CoraFixMeException,
          "Issue hidden by CORAFIXME marker message is incorrect (should be #{message.inspect} but was #{captured.message.inspect})"
  when :wrong_class
    raise CoraFixMeException,
          "Issue hidden by CORAFIXME marker class is incorrect. Expected #{exception}, was #{captured.class}"
  end
end

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

class EqlMatcher
  def initialize(expected)
    @expected = expected
  end

  def matches?(actual)
    actual.eql?(@expected)
  end

  def failure_message(actual)
    "Expected #{actual.inspect} to eql #{@expected.inspect}"
  end
end

class IncludeMatcher
  def initialize(*expected)
    @expected = expected
  end

  def matches?(actual)
    i = 0
    while i < @expected.size
      item = @expected[i]
      return false unless actual.include?(item)
      i += 1
    end
    true
  end

  def failure_message(actual)
    "Expected #{actual.inspect} to include #{@expected.inspect}"
  end
end

class KindOfMatcher
  def initialize(expected_class)
    @expected_class = expected_class
  end

  def matches?(actual)
    actual.is_a?(@expected_class)
  end

  def failure_message(actual)
    "Expected #{actual.inspect} to be kind of #{@expected_class}"
  end
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

class BeNilMatcher
  def matches?(actual)
    actual.nil?
  end

  def failure_message(actual)
    "Expected #{actual.inspect} to be nil"
  end
end

class BeEmptyMatcher
  def matches?(actual)
    actual.empty?
  end

  def failure_message(actual)
    "Expected #{actual.inspect} to be empty"
  end
end

class RespondToMatcher
  def initialize(name, include_private = false)
    @name = name
    @include_private = include_private
  end

  def matches?(actual)
    actual.respond_to?(@name, @include_private)
  end

  def failure_message(actual)
    "Expected #{actual.inspect} to respond to #{@name.inspect}"
  end
end

class BeCloseMatcher
  def initialize(expected, tolerance)
    @expected = expected
    @tolerance = tolerance
  end

  def matches?(actual)
    (actual - @expected).abs <= @tolerance
  end

  def failure_message(actual)
    "Expected #{actual.inspect} to be within #{@tolerance.inspect} of #{@expected.inspect}"
  end
end

class HaveMethodMatcher
  def initialize(name)
    @name = name
  end

  def matches?(actual)
    actual.respond_to?(@name, true)
  end

  def failure_message(actual)
    "Expected #{actual.inspect} to have method #{@name.inspect}"
  end
end

class HaveConstantMatcher
  def initialize(name)
    @name = name
  end

  def matches?(actual)
    actual.const_defined?(@name)
  end

  def failure_message(actual)
    "Expected #{actual.inspect} to have constant #{@name.inspect}"
  end
end

class HaveInstanceMethodMatcher
  def initialize(name, visibility, include_super = true)
    @name = name
    @visibility = visibility
    @include_super = include_super
  end

  def matches?(actual)
    list = case @visibility
    when :public then actual.public_instance_methods(@include_super)
    when :private then actual.private_instance_methods(@include_super)
    when :protected then actual.protected_instance_methods(@include_super)
    else actual.instance_methods(@include_super)
    end
    list.include?(@name)
  end

  def failure_message(actual)
    "Expected #{actual.inspect} to have #{@visibility} instance method #{@name.inspect}"
  end
end

class HavePrivateMethodMatcher
  def initialize(name)
    @name = name
  end

  def matches?(actual)
    actual.private_methods.include?(@name)
  end

  def failure_message(actual)
    "Expected #{actual.inspect} to have private method #{@name.inspect}"
  end
end

class BeComputedByMatcher
  def initialize(method_name, *extra_args)
    @method_name = method_name
    @extra_args = extra_args
  end

  def matches?(actual)
    actual.each do |tuple|
      return false unless tuple.is_a?(Array) && tuple.length >= 2
      receiver = tuple[0]
      expected = tuple[-1]
      method_args = tuple[1...-1] || []
      result = receiver.send(@method_name, *method_args, *@extra_args)
      return false unless result == expected
    end
    true
  end

  def failure_message(actual)
    "Expected #{actual.inspect} to be computed by #{@method_name}"
  end
end

class SpecCaptureIO
  attr_reader :string

  def initialize
    @string = ""
  end

  def write(value)
    @string = @string + value.to_s
    value.to_s.length
  end

  def <<(value)
    write(value)
    self
  end

  def print(*args)
    args.each { |a| write(a.to_s) }
    nil
  end

  def puts(*args)
    if args.length == 0
      write("\n")
      return nil
    end
    args.each do |a|
      s = a.to_s
      if s.end_with?("\n")
        write(s)
      else
        write(s + "\n")
      end
    end
    nil
  end

  def flush
    nil
  end
end

class OutputMatcher
  def initialize(expected_stdout = nil, expected_stderr = nil, fd = nil)
    @expected_stdout = expected_stdout
    @expected_stderr = expected_stderr
    @fd = fd
    @actual_stdout = nil
    @actual_stderr = nil
  end

  def matches?(callable)
    return false unless callable.respond_to?(:call)

    out = SpecCaptureIO.new
    err = SpecCaptureIO.new
    old_out = $stdout
    old_err = $stderr
    $stdout = out
    $stderr = err
    begin
      callable.call
    ensure
      $stdout = old_out
      $stderr = old_err
    end

    @actual_stdout = out.string
    @actual_stderr = err.string
    matches_output?
  end

  def matches_output?
    if @fd
      actual = fd_string(@fd)
      expected = @expected_stdout
      return match_value?(expected, actual)
    end

    return false unless match_value?(@expected_stdout, @actual_stdout)
    return false unless match_value?(@expected_stderr, @actual_stderr)
    true
  end

  def fd_string(fd)
    if fd == 2 || fd == STDERR
      @actual_stderr
    else
      @actual_stdout
    end
  end

  def match_value?(expected, actual)
    return true if expected.nil?
    if expected.is_a?(Regexp)
      !(actual =~ expected).nil?
    else
      actual == expected
    end
  end

  def failure_message(_actual)
    "Expected output did not match"
  end
end

class ComplainMatcher
  def initialize(expected = nil, _opts = nil)
    @expected = expected
    @actual = nil
  end

  def matches?(callable)
    return false unless callable.respond_to?(:call)

    err = SpecCaptureIO.new
    old_err = $stderr
    $stderr = err
    begin
      callable.call
    ensure
      $stderr = old_err
    end
    @actual = err.string

    if @expected.nil?
      @actual != ""
    elsif @expected.is_a?(Regexp)
      !(@actual =~ @expected).nil?
    else
      @actual == @expected
    end
  end

  def failure_message(_actual)
    "Expected warning output to match #{@expected.inspect}, got #{@actual.inspect}"
  end
end

class RaiseErrorMatcher
  def initialize(expected_class = nil, expected_message = nil, verifier = nil)
    @expected_class = expected_class
    @expected_message = expected_message
    @verifier = verifier
    @actual_exception = nil
  end

  def matches?(actual)
    unless actual.respond_to?(:call)
      return false
    end

    begin
      actual.call
      @actual_exception = nil
      return false
    rescue Exception => e
      @actual_exception = e
    end

    return false unless match_class?
    return false unless match_message?
    @verifier.call(@actual_exception) if @verifier
    true
  end

  def match_class?
    return true if @expected_class.nil?
    if @expected_class.is_a?(Module)
      @actual_exception.is_a?(@expected_class)
    else
      true
    end
  end

  def match_message?
    return true if @expected_message.nil?
    if @expected_message.is_a?(Regexp)
      !(@actual_exception.message =~ @expected_message).nil?
    else
      @actual_exception.message == @expected_message
    end
  end

  def failure_message(actual)
    unless actual.respond_to?(:call)
      return "Expected callable object, got #{actual.inspect}"
    end

    if @actual_exception.nil?
      "Expected block to raise an error, but no error was raised"
    else
      "Expected raise_error(#{@expected_class.inspect}, #{@expected_message.inspect}), got #{@actual_exception.class}: #{@actual_exception.message}"
    end
  end
end

def equal(expected)
  EqualMatcher.new(expected)
end

def eql(expected)
  EqlMatcher.new(expected)
end

def include(*expected)
  IncludeMatcher.new(*expected)
end

def be_kind_of(expected_class)
  KindOfMatcher.new(expected_class)
end

def be_a(expected_class)
  be_kind_of(expected_class)
end

def be_an_instance_of(expected_class)
  BeAnInstanceOfMatcher.new(expected_class)
end

def be_true
  BooleanMatcher.new(true)
end

def be_false
  BooleanMatcher.new(false)
end

def be_nil
  BeNilMatcher.new
end

def be_empty
  BeEmptyMatcher.new
end

def respond_to(name, include_private = false)
  RespondToMatcher.new(name, include_private)
end

def be_close(expected, tolerance)
  BeCloseMatcher.new(expected, tolerance)
end

def have_method(name)
  HaveMethodMatcher.new(name)
end

def have_constant(name)
  HaveConstantMatcher.new(name)
end

def have_instance_method(name, include_super = true)
  HaveInstanceMethodMatcher.new(name, :any, include_super)
end

def have_public_instance_method(name, include_super = true)
  HaveInstanceMethodMatcher.new(name, :public, include_super)
end

def have_private_instance_method(name, include_super = true)
  HaveInstanceMethodMatcher.new(name, :private, include_super)
end

def have_protected_instance_method(name, include_super = true)
  HaveInstanceMethodMatcher.new(name, :protected, include_super)
end

def have_private_method(name)
  HavePrivateMethodMatcher.new(name)
end

def be_computed_by(method_name, *extra_args)
  BeComputedByMatcher.new(method_name, *extra_args)
end

def output(expected_stdout = nil, expected_stderr = nil)
  OutputMatcher.new(expected_stdout, expected_stderr, nil)
end

def output_to_fd(expected_output = nil, fd = nil)
  OutputMatcher.new(expected_output, nil, fd || 1)
end

def complain(expected = nil, opts = nil)
  ComplainMatcher.new(expected, opts)
end

def suppress_warning
  yield
end

def raise_error(expected = nil, expected_message = nil, &verifier)
  expected_class = nil
  message = expected_message

  if expected.is_a?(Module)
    expected_class = expected
  elsif expected.is_a?(String) || expected.is_a?(Regexp)
    message = expected
  end

  RaiseErrorMatcher.new(expected_class, message, verifier)
end

class SpecMockExpectation
  def initialize(mock_name, method_name)
    @mock_name = mock_name
    @method_name = method_name
    @expected_args = nil
    @calls = 0
    @min_calls = 1
    @max_calls = 1
    @return_values = []
    @raise_value = nil
    @yield_values = []
    @pending_exactly = nil
  end

  def with(*args)
    @expected_args = args
    self
  end

  def and_return(*values)
    @return_values = values
    self
  end

  def and_raise(value = RuntimeError)
    @raise_value = value
    self
  end

  def and_yield(*values)
    @yield_values << values
    self
  end

  def once
    @min_calls = 1
    @max_calls = 1
    self
  end

  def twice
    @min_calls = 2
    @max_calls = 2
    self
  end

  def exactly(n)
    @pending_exactly = n
    self
  end

  def at_least(n)
    @min_calls = n
    @max_calls = nil
    self
  end

  def at_most(n)
    @min_calls = 0
    @max_calls = n
    self
  end

  def any_number_of_times
    @min_calls = 0
    @max_calls = nil
    self
  end

  def times
    if !@pending_exactly.nil?
      @min_calls = @pending_exactly
      @max_calls = @pending_exactly
      @pending_exactly = nil
    end
    self
  end

  def ordered
    self
  end

  def invoke(args, block = nil)
    if !@expected_args.nil? && @expected_args != args
      raise SpecFailedException, "Expected #{@mock_name}.#{@method_name}(#{@expected_args.inspect}), got args #{args.inspect}"
    end

    @calls += 1

    if !@max_calls.nil? && @calls > @max_calls
      raise SpecFailedException, "Expected #{@mock_name}.#{@method_name} at most #{@max_calls} times, got #{@calls}"
    end

    if !@raise_value.nil?
      if @raise_value.is_a?(Class)
        raise @raise_value
      else
        raise @raise_value
      end
    end

    if @yield_values.length > 0 && !block.nil?
      @yield_values.each do |vals|
        block.call(*vals)
      end
    end

    if @return_values.length == 0
      nil
    elsif @calls <= @return_values.length
      @return_values[@calls - 1]
    else
      @return_values[@return_values.length - 1]
    end
  end

  def verify!
    if @calls < @min_calls
      raise SpecFailedException, "Expected #{@mock_name}.#{@method_name} at least #{@min_calls} times, got #{@calls}"
    end
  end
end

class MockObject
  def initialize(name = nil)
    @name = name || "mock"
    @forbidden_calls = {}
    @expected_calls = {}
    @wrapped_methods = {}
  end

  def should_not_receive(method_name)
    method_name = method_name.to_sym
    @expected_calls.delete(method_name)
    @forbidden_calls[method_name] = true
    install_method_wrapper(method_name)
    self
  end

  def should_receive(method_name)
    method_name = method_name.to_sym
    @forbidden_calls.delete(method_name)
    exp = SpecMockExpectation.new(@name, method_name)
    @expected_calls[method_name] = exp
    install_method_wrapper(method_name)
    exp
  end

  def verify_expectations!
    keys = @expected_calls.keys
    i = 0
    while i < keys.length
      @expected_calls[keys[i]].verify!
      i += 1
    end
    restore_method_wrappers
  end

  def method_missing(name, *args, &block)
    sym = name.to_sym

    if @forbidden_calls[sym]
      raise SpecFailedException, "Expected #{@name} not to receive #{name}"
    end

    exp = @expected_calls[sym]
    return exp.invoke(args, block) if exp

    nil
  end

  def respond_to_missing?(_name, _include_private = false)
    true
  end

  private

  def install_method_wrapper(method_name)
    already_wrapped = false
    @wrapped_methods.each do |name, _|
      if name == method_name
        already_wrapped = true
      end
    end
    return if already_wrapped

    singleton = class << self; self; end
    unless singleton.instance_methods.include?(method_name)
      @wrapped_methods[method_name] = nil
      return
    end

    original_name = "__spec_mock_original_#{object_id}_#{method_name}".to_sym
    singleton.send(:alias_method, original_name, method_name)
    @wrapped_methods[method_name] = original_name

    define_singleton_method(method_name) do |*args, &block|
      if @forbidden_calls[method_name]
        raise SpecFailedException, "Expected #{@name} not to receive #{method_name}"
      end

      exp = @expected_calls[method_name]
      return exp.invoke(args, block) if exp

      send(original_name, *args, &block)
    end
  end

  def restore_method_wrappers
    singleton = class << self; self; end
    method_names = @wrapped_methods.keys
    i = 0
    while i < method_names.length
      method_name = method_names[i]
      original_name = @wrapped_methods[method_name]
      if !original_name.nil?
        singleton.send(:alias_method, method_name, original_name)
        begin
          singleton.send(:remove_method, original_name)
        rescue NameError
          nil
        end
      end
      i += 1
    end
    @wrapped_methods = {}
  end
end

class SpecUnboundMethod
  def initialize(owner, method_name)
    @owner = owner
    @method_name = method_name.to_sym
  end

  def arity
    if @owner == Enumerator && @method_name == :each
      -1
    else
      0
    end
  end
end

class Module
  def instance_method(name)
    SpecUnboundMethod.new(self, name)
  end
end

def mock(name = nil)
  m = MockObject.new(name)
  $__active_mocks << m
  m
end

class ExpectationTarget
  def initialize(actual)
    @actual = actual
  end

  def to(matcher)
    SpecExpectation.new(@actual).match(matcher)
  end

  def not_to(matcher)
    SpecNegatedExpectation.new(@actual).match(matcher)
  end
end

def expect(actual)
  ExpectationTarget.new(actual)
end

class Object
  def __spec_method_hooks
    @__spec_method_hooks ||= {}
  end

  def __spec_hooked_methods
    @__spec_hooked_methods ||= []
  end

  def __spec_expected_calls
    @__spec_expected_calls ||= {}
  end

  def __spec_forbidden_calls
    @__spec_forbidden_calls ||= {}
  end

  def __spec_install_hook(method_name)
    method_name = method_name.to_sym
    return if __spec_hooked_methods.include?(method_name)

    original = nil
    begin
      original = method(method_name)
    rescue NameError
      original = nil
    end

    __spec_method_hooks[method_name] = original
    __spec_hooked_methods << method_name
    define_singleton_method(method_name) do |*args, &block|
      __spec_dispatch_mock_call(method_name, args, block)
    end
  end

  def __spec_dispatch_mock_call(method_name, args, block)
    sym = method_name.to_sym
    if __spec_forbidden_calls[sym]
      raise SpecFailedException, "Expected #{self.inspect} not to receive #{sym}"
    end

    exp = __spec_expected_calls[sym]
    return exp.invoke(args, block) if exp

    original = __spec_method_hooks[sym]
    return original.call(*args, &block) unless original.nil?

    nil
  end

  def __spec_restore_hooks
    singleton = class << self; self; end
    __spec_hooked_methods.each do |name|
      original = __spec_method_hooks[name]
      if original.nil?
        begin
          singleton.__send__(:remove_method, name)
        rescue NameError
          nil
        end
      else
        define_singleton_method(name) do |*args, &block|
          original.call(*args, &block)
        end
      end
    end
    @__spec_method_hooks = {}
    @__spec_hooked_methods = []
    @__spec_expected_calls = {}
    @__spec_forbidden_calls = {}
  end

  def should_receive(method_name)
    method_name = method_name.to_sym
    __spec_install_hook(method_name)
    __spec_forbidden_calls.delete(method_name)
    exp = SpecMockExpectation.new(self.class.to_s, method_name)
    __spec_expected_calls[method_name] = exp
    already_registered = false
    $__active_mocks.each do |entry|
      if entry.equal?(self)
        already_registered = true
        break
      end
    end
    $__active_mocks << self unless already_registered
    exp
  end

  def should_not_receive(method_name)
    method_name = method_name.to_sym
    __spec_install_hook(method_name)
    __spec_expected_calls.delete(method_name)
    __spec_forbidden_calls[method_name] = true
    already_registered = false
    $__active_mocks.each do |entry|
      if entry.equal?(self)
        already_registered = true
        break
      end
    end
    $__active_mocks << self unless already_registered
    self
  end

  def stub!(method_name)
    should_receive(method_name).any_number_of_times
  end

  def verify_expectations!
    begin
      __spec_expected_calls.each do |_name, exp|
        exp.verify!
      end
    ensure
      __spec_restore_hooks
    end
  end

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
  if ENV["CORA_SPEC_STATS"] == "1"
    failed = $__failures.length
    skipped = $__skipped.length
    puts "__cora_spec_stats__ total=#{$__examples_total} passed=#{$__passes} failed=#{failed} skipped=#{skipped}"
  end
end

at_exit do
  run_spec_suite
  report_results
end
