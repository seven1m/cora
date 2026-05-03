require_relative '../../spec_helper'
require_relative '../../fixtures/code_loading'
require_relative 'fixtures/classes'

describe "Module#autoload?" do
  it "returns the name of the file that will be autoloaded" do
    ModuleSpecs::Autoload.autoload :Autoload, "autoload.rb"
    ModuleSpecs::Autoload.autoload?(:Autoload).should == "autoload.rb"
  end

  it "returns nil if no file has been registered for a constant" do
    ModuleSpecs::Autoload.autoload?(:Manualload).should be_nil
  end

  it "returns the name of the file that will be autoloaded if an ancestor defined that autoload" do
    ModuleSpecs::Autoload::Parent.autoload :AnotherAutoload, "another_autoload.rb"
    ModuleSpecs::Autoload::Child.autoload?(:AnotherAutoload).should == "another_autoload.rb"
  end

  it "returns nil if an ancestor defined that autoload but recursion is disabled" do
    ModuleSpecs::Autoload::Parent.autoload :InheritedAutoload, "inherited_autoload.rb"
    ModuleSpecs::Autoload::Child.autoload?(:InheritedAutoload, false).should be_nil
  end

  it "returns the name of the file that will be loaded if recursion is disabled but the autoload is defined on the class itself" do
    ModuleSpecs::Autoload::Child.autoload :ChildAutoload, "child_autoload.rb"
    ModuleSpecs::Autoload::Child.autoload?(:ChildAutoload, false).should == "child_autoload.rb"
  end
end

describe "Module#autoload" do
  before :all do
    @non_existent = fixture __FILE__, "no_autoload.rb"
    CodeLoadingSpecs.preload_rubygems
  end

  before :each do
    @loaded_features = $".dup

    ScratchPad.clear
    @remove = []
  end

  after :each do
    $".replace @loaded_features
    @remove.each { |const|
      ModuleSpecs::Autoload.send :remove_const, const
    }
  end

  it "registers a file to load the first time the named constant is accessed" do
    ModuleSpecs::Autoload.autoload :A, @non_existent
    ModuleSpecs::Autoload.autoload?(:A).should == @non_existent
  end

  it "sets the autoload constant in the constants table" do
    ModuleSpecs::Autoload.autoload :B, @non_existent
    ModuleSpecs::Autoload.should have_constant(:B)
  end

  it "loads the registered constant when it is accessed" do
    ModuleSpecs::Autoload.should_not have_constant(:X)
    ModuleSpecs::Autoload.autoload :X, fixture(__FILE__, "autoload_x.rb")
    @remove << :X
    ModuleSpecs::Autoload::X.should == :x
  end

  it "does not load the file when the constant is already set" do
    ModuleSpecs::Autoload.autoload :I, fixture(__FILE__, "autoload_i.rb")
    @remove << :I
    ModuleSpecs::Autoload.const_set :I, 3
    ModuleSpecs::Autoload::I.should == 3
    ScratchPad.recorded.should be_nil
  end

  it "loads a file with .rb extension when passed the name without the extension" do
    ModuleSpecs::Autoload.autoload :J, fixture(__FILE__, "autoload_j")
    ModuleSpecs::Autoload::J.should == :autoload_j
  end

  it "calls main.require(path) to load the file" do
    ModuleSpecs::Autoload.autoload :ModuleAutoloadCallsRequire, "module_autoload_not_exist.rb"
    main = TOPLEVEL_BINDING.eval("self")
    main.should_receive(:require).with("module_autoload_not_exist.rb")
    -> { ModuleSpecs::Autoload::ModuleAutoloadCallsRequire }.should raise_error(NameError)
  end
end
