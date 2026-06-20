require_relative '../../spec_helper'

describe "ENV.empty?" do

  it "returns true if the Environment is empty" do
    CORAFIXME "ENV.keys not implemented", exception: NoMethodError do
      if ENV.keys.size > 0
        ENV.should_not.empty?
      end
    end
    orig = ENV.to_hash
    begin
      ENV.clear
      ENV.should.empty?
    ensure
      ENV.replace orig
    end
  end

  it "returns false if not empty" do
    CORAFIXME "ENV.keys not implemented", exception: NoMethodError do
      if ENV.keys.size > 0
        ENV.should_not.empty?
      end
    end
  end
end
