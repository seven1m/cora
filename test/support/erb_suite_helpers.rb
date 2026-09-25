require "test/unit"
require "stringio"

module EnvUtil
  def self.suppress_warning
    previous = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = previous
  end
end

module Test::Unit::Assertions
  def assert_warning(pattern)
    previous = $stderr
    captured = StringIO.new
    $stderr = captured
    begin
      yield
    ensure
      $stderr = previous
    end
    assert_match(pattern, captured.string)
  end
end
