require_relative '../spec_helper'
require 'stringio'

# ruby/spec's predefined_spec.rb documents $> but has no examples for its alias.
describe "Predefined global $>" do
  before :each do
    @stdout = $stdout
  end

  after :each do
    $stdout = @stdout
  end

  it "aliases $stdout" do
    $>.should equal($stdout)
  end

  it "follows reassignment of $stdout" do
    output = StringIO.new
    $stdout = output
    $>.should equal(output)
    print "from stdout"
    output.string.should == "from stdout"
  end

  it "updates $stdout when reassigned" do
    output = StringIO.new
    $> = output
    $stdout.should equal(output)
    printf "%s", "from output"
    output.string.should == "from output"
  end
end
