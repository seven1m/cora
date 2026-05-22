require_relative '../../spec_helper'
require_relative 'fixtures/class_eval_minimal'
require_relative 'shared/class_eval'

describe "Module#class_eval" do
  it_behaves_like :module_class_eval, :class_eval
end
