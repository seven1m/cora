require_relative '../../spec_helper'

describe "ObjectSpace.define_finalizer" do
  it "raises an ArgumentError if the action does not respond to call" do
    -> {
      ObjectSpace.define_finalizer(Object.new, mock("ObjectSpace.define_finalizer no #call"))
    }.should.raise(ArgumentError)
  end

  it "accepts an object and a proc" do
    handler = -> id { id }
    ObjectSpace.define_finalizer(Object.new, handler).should == [0, handler]
  end

  it "accepts an object and a bound method" do
    handler = mock("callable")
    def handler.finalize(id) end
    finalize = handler.method(:finalize)
    ObjectSpace.define_finalizer(Object.new, finalize).should == [0, finalize]
  end

  it "accepts an object and a callable" do
    handler = mock("callable")
    def handler.call(id) end
    ObjectSpace.define_finalizer(Object.new, handler).should == [0, handler]
  end

  it "accepts an object and a block" do
    handler = -> id { id }
    ObjectSpace.define_finalizer(Object.new, &handler).should == [0, handler]
  end

  it "raises ArgumentError trying to define a finalizer on a non-reference" do
    -> {
      ObjectSpace.define_finalizer(:blah) { 1 }
    }.should.raise(ArgumentError)
  end

  it "calls finalizer on process termination" do
    code = <<-RUBY
      def scoped
        Proc.new { puts "finalizer run" }
      end
      handler = scoped
      obj = +"Test"
      ObjectSpace.define_finalizer(obj, handler)
      exit 0
    RUBY

    ruby_exe(code, :args => "2>&1").should.include?("finalizer run\n")
  end

  it "allows multiple finalizers with different 'callables' to be defined" do
    code = <<-'RUBY'
      obj = Object.new

      ObjectSpace.define_finalizer(obj, Proc.new { STDOUT.write "finalized1\n" })
      ObjectSpace.define_finalizer(obj, Proc.new { STDOUT.write "finalized2\n" })

      exit 0
    RUBY

    ruby_exe(code).lines.sort.should == ["finalized1\n", "finalized2\n"]
  end
end
