require_relative '../../spec_helper'

describe "UnboundMethod#parameters for captured methods" do
  it "keeps the parameters after the method is removed" do
    klass = Class.new do
      def value(arg); end
    end
    method = klass.instance_method(:value)
    klass.class_eval { remove_method :value }

    method.parameters.should == [[:req, :arg]]
  end

  it "keeps the original parameters after the method is redefined" do
    klass = Class.new do
      def value(arg); end
    end
    method = klass.instance_method(:value)
    klass.class_eval do
      def value; end
    end

    method.parameters.should == [[:req, :arg]]
  end
end
