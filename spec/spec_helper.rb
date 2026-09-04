use_realpath = File.respond_to?(:realpath)
root = __dir__
dir = "fixtures/code"
CODE_LOADING_DIR = use_realpath ? File.realpath(dir, root) : File.expand_path(dir, root)

# Enable Thread.report_on_exception by default to catch thread errors earlier.
if Thread.respond_to? :report_on_exception=
  Thread.report_on_exception = true
else
  class Thread
    def report_on_exception=(value)
      raise "shim Thread#report_on_exception used with true" if value
    end
  end
end

unless ENV['MSPEC_RUNNER'] # Running directly with cora some_spec.rb
  mspec_lib = File.expand_path('../ext/mspec/lib', __dir__)
  $LOAD_PATH << mspec_lib if File.directory?(mspec_lib)
  RUBY_EXE = File.expand_path('../build/bin/cora', __dir__) unless defined?(RUBY_EXE)

  begin
    require 'mspec'
    require 'mspec/utils/script'
    require 'mspec/runner/formatters/dotted'
  rescue LoadError
    puts "Please initialize the ext/mspec submodule to run the specs."
    exit 1
  end

  # Local specs still contain deprecated matcher spellings while they are
  # being synchronized with current ruby/spec. Avoid overflowing the embedded
  # runner's diagnostic buffer with one warning per expectation.
  module MSpec
    def self.deprecate(_what, _replacement)
    end
  end

  class CoraSpecStatsAction
    def register
      MSpec.register :finish, self
    end

    def finish
      tally = MSpec.formatter.tally.counter
      skipped = MSpec.skips.length
      unhandled = !$!.nil?
      failed = tally.failures + tally.errors + (unhandled ? 1 : 0)
      passed = [tally.examples - failed - skipped, 0].max

      puts "OK: #{passed} passed" if failed == 0
      if ENV['CORA_SPEC_STATS'] == '1'
        puts "__cora_spec_stats__ total=#{tally.examples} passed=#{passed} failed=#{failed} skipped=#{skipped}"
      end
      exit 1 if failed > 0 && !unhandled
    end
  end

  formatter = DottedFormatter.new
  formatter.register
  MSpec.formatter = formatter
  CoraSpecStatsAction.new.register
  MSpec.setup_env
  MSpec.actions :start
  MSpec.actions :load
end

class CoraFixMeException < StandardError
end

SpecFailedException = SpecExpectationNotMetError unless defined?(SpecFailedException)

def fixnum_max
  (2**62) - 1
end

def fixnum_min
  -(2**62)
end

def xit(description, &block)
  it(description) { skip 'temporarily disabled' }
end

def CORAFIXME(description, exception: StandardError, message: nil, condition: true)
  raise SpecFailedException, "CORAFIXME requires a block" unless block_given?
  return yield unless condition

  MSpec.expectation
  MSpec.actions :expectation, MSpec.current.state

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

  captured = nil
  status = begin
    yield
    :unexpected_pass
  rescue exception => error
    captured = error
    matcher.call(error.message) ? :valid_fixme : :wrong_message
  rescue Exception => error
    captured = error
    :wrong_class
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

# Compare with SpecVersion directly here so it works even with --unguarded.
if VersionGuard::FULL_RUBY_VERSION < SpecVersion.new('3.3')
  abort "This version of ruby/spec requires Ruby 3.3+"
end

unless ENV['MSPEC_RUNNER'] # Running directly with cora some_spec.rb
  at_exit do
    MSpec.actions :finish
  end
end
