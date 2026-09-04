require_relative '../../spec_helper'

describe "Refinement#prepend" do
  # Cora does not implement refinements yet; the spec-helper shim does not
  # execute this block.
  xit "raises a TypeError" do
    Module.new do
      refine String do
        -> {
          prepend Module.new
        }.should.raise(TypeError, "Refinement#prepend has been removed")
      end
    end
  end
end
