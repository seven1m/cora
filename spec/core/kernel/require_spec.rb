require_relative '../../spec_helper'
require_relative '../../fixtures/code_loading'

CODE_LOADING_DIR = File.expand_path("../../fixtures/code", __dir__)

describe "Kernel#require" do
  before :each do
    CodeLoadingSpecs.spec_setup
    @object = CodeLoadingSpecs::Method.new
  end

  after :each do
    CodeLoadingSpecs.spec_cleanup
  end

  it "loads an absolute path" do
    path = File.expand_path("load_fixture.rb", CODE_LOADING_DIR)
    @object.require(path).should be_true
    ScratchPad.recorded.should == [:loaded]
  end

  it "loads a file defining many methods" do
    path = File.expand_path("methods_fixture.rb", CODE_LOADING_DIR)
    @object.require(path).should be_true
    ScratchPad.recorded.should == [:loaded]
  end

  it "loads a non-canonical absolute path" do
    path = File.join(CODE_LOADING_DIR, "..", "code", "load_fixture.rb")
    @object.require(path).should be_true
    ScratchPad.recorded.should == [:loaded]
  end

  it "raises a LoadError if the file does not exist" do
    path = File.expand_path("nonexistent.rb", CODE_LOADING_DIR)
    File.should_not.exist?(path)
    -> { @object.require(path) }.should raise_error(LoadError)
    ScratchPad.recorded.should == []
  end

  it "raises a TypeError if passed nil" do
    -> { @object.require(nil) }.should raise_error(TypeError)
  end

  it "raises a TypeError if passed an Integer" do
    -> { @object.require(42) }.should raise_error(TypeError)
  end

  it "raises a TypeError if passed an Array" do
    -> { @object.require([]) }.should raise_error(TypeError)
  end

  it "loads a ./ relative path from the current working directory with empty $LOAD_PATH" do
    Dir.chdir(CODE_LOADING_DIR) do
      @object.require("./load_fixture.rb").should be_true
    end
    ScratchPad.recorded.should == [:loaded]
  end

  it "loads a ../ relative path from the current working directory with empty $LOAD_PATH" do
    Dir.chdir(CODE_LOADING_DIR) do
      @object.require("../code/load_fixture.rb").should be_true
    end
    ScratchPad.recorded.should == [:loaded]
  end

  it "loads a ./ relative path from the current working directory with non-empty $LOAD_PATH" do
    $LOAD_PATH << "an_irrelevant_dir"
    Dir.chdir(CODE_LOADING_DIR) do
      @object.require("./load_fixture.rb").should be_true
    end
    ScratchPad.recorded.should == [:loaded]
  end

  it "loads a ../ relative path from the current working directory with non-empty $LOAD_PATH" do
    $LOAD_PATH << "an_irrelevant_dir"
    Dir.chdir(CODE_LOADING_DIR) do
      @object.require("../code/load_fixture.rb").should be_true
    end
    ScratchPad.recorded.should == [:loaded]
  end

  it "resolves a filename against $LOAD_PATH entries" do
    $LOAD_PATH << CODE_LOADING_DIR
    @object.require("load_fixture.rb").should be_true
    ScratchPad.recorded.should == [:loaded]
  end

  it "does not require file twice after $LOAD_PATH change" do
    $LOAD_PATH << CODE_LOADING_DIR
    @object.require("load_fixture.rb").should be_true
    $LOAD_PATH.push CODE_LOADING_DIR + "/gem"
    @object.require("load_fixture.rb").should be_false
    ScratchPad.recorded.should == [:loaded]
  end

  it "does not resolve a ./ relative path against $LOAD_PATH entries" do
    $LOAD_PATH << CODE_LOADING_DIR
    -> { @object.require("./load_fixture.rb") }.should raise_error(LoadError)
    ScratchPad.recorded.should == []
  end

  it "does not resolve a ../ relative path against $LOAD_PATH entries" do
    $LOAD_PATH << CODE_LOADING_DIR
    -> { @object.require("../code/load_fixture.rb") }.should raise_error(LoadError)
    ScratchPad.recorded.should == []
  end

  it "resolves a non-canonical path against $LOAD_PATH entries" do
    $LOAD_PATH << File.dirname(CODE_LOADING_DIR)
    @object.require("code/../code/load_fixture.rb").should be_true
    ScratchPad.recorded.should == [:loaded]
  end

  it "stores the missing path in a LoadError object" do
    path = "abcd1234"

    -> { @object.require(path) }.should raise_error(LoadError) { |e|
      e.path.should == path
    }
  end

  it "stores an absolute path" do
    path = File.expand_path("load_fixture.rb", CODE_LOADING_DIR)
    @object.require(path).should be_true
    $LOADED_FEATURES.should include(path)
  end

  it "does not load an absolute path that is already stored" do
    path = File.expand_path("load_fixture.rb", CODE_LOADING_DIR)
    $LOADED_FEATURES << path
    @object.require(path).should be_false
    ScratchPad.recorded.should == []
  end

  it "does not load a ./ relative path that is already stored" do
    $LOADED_FEATURES << "./load_fixture.rb"
    Dir.chdir(CODE_LOADING_DIR) do
      @object.require("./load_fixture.rb").should be_false
    end
    ScratchPad.recorded.should == []
  end

  it "does not load a ../ relative path that is already stored" do
    $LOADED_FEATURES << "../load_fixture.rb"
    Dir.chdir(CODE_LOADING_DIR) do
      @object.require("../load_fixture.rb").should be_false
    end
    ScratchPad.recorded.should == []
  end

  it "does not load a non-canonical path that is already stored" do
    $LOADED_FEATURES << "code/../code/load_fixture.rb"
    $LOAD_PATH << File.dirname(CODE_LOADING_DIR)
    @object.require("code/../code/load_fixture.rb").should be_false
    ScratchPad.recorded.should == []
  end

  it "respects being replaced with a new array" do
    prev = $LOADED_FEATURES.dup
    path = File.expand_path("load_fixture.rb", CODE_LOADING_DIR)

    @object.require(path).should be_true
    $LOADED_FEATURES.should include(path)

    $LOADED_FEATURES.replace(prev)

    $LOADED_FEATURES.should_not include(path)
    @object.require(path).should be_true
    $LOADED_FEATURES.should include(path)
  end

  it "does not load twice the same file with and without extension" do
    $LOAD_PATH << CODE_LOADING_DIR
    @object.require("load_fixture.rb").should be_true
    @object.require("load_fixture").should be_false
  end

  it "loads a .rb extensioned file when a non extensioned file is in $LOADED_FEATURES" do
    $LOADED_FEATURES << "load_fixture"
    $LOAD_PATH << CODE_LOADING_DIR
    @object.require("load_fixture").should be_true
    ScratchPad.recorded.should == [:loaded]
  end

  it "loads a .rb extensioned file from a subdirectory when a non extensioned file is in $LOADED_FEATURES" do
    $LOADED_FEATURES << "load_fixture"
    $LOAD_PATH << File.dirname(CODE_LOADING_DIR)
    @object.require("code/load_fixture").should be_true
    ScratchPad.recorded.should == [:loaded]
  end

  it "returns false if a bare file is in $LOADED_FEATURES and the file is not found" do
    $LOADED_FEATURES << "load_fixture"
    Dir.chdir(File.dirname(CODE_LOADING_DIR)) do
      @object.require("load_fixture").should be_false
      ScratchPad.recorded.should == []
    end
  end

  it "returns false when a path is in $LOADED_FEATURES and the file is not found" do
    $LOADED_FEATURES << "code/load_fixture"
    Dir.chdir(CODE_LOADING_DIR) do
      @object.require("code/load_fixture").should be_false
      ScratchPad.recorded.should == []
    end
  end

  it "stores ../ relative paths as absolute paths" do
    path = File.expand_path("load_fixture.rb", CODE_LOADING_DIR)
    Dir.chdir(CODE_LOADING_DIR) do
      @object.require("../code/load_fixture.rb").should be_true
    end
    $LOADED_FEATURES.should include(path)
  end

  it "stores ./ relative paths as absolute paths" do
    path = File.expand_path("load_fixture.rb", CODE_LOADING_DIR)
    Dir.chdir(CODE_LOADING_DIR) do
      @object.require("./load_fixture.rb").should be_true
    end
    $LOADED_FEATURES.should include(path)
  end

  it "expands absolute paths containing .." do
    path = File.expand_path("load_fixture.rb", CODE_LOADING_DIR)
    non_canonical = File.join(CODE_LOADING_DIR, "..", "code", "load_fixture.rb")
    @object.require(non_canonical).should be_true
    $LOADED_FEATURES.should include(path)
  end

  platform_is_not :windows do
    describe "with symlinks" do
      before :each do
        @symlink_to_code_dir = tmp("codesymlink")
        rm_r @symlink_to_code_dir
        File.symlink(CODE_LOADING_DIR, @symlink_to_code_dir)

        $LOAD_PATH.delete(CODE_LOADING_DIR)
        $LOAD_PATH.unshift(@symlink_to_code_dir)
      end

      after :each do
        rm_r @symlink_to_code_dir
      end

      it "does not canonicalize the path and stores a path with symlinks" do
        symlink_path = "#{@symlink_to_code_dir}/load_fixture.rb"
        canonical_path = "#{CODE_LOADING_DIR}/load_fixture.rb"
        @object.require(symlink_path).should be_true
        ScratchPad.recorded.should == [:loaded]

        features = $LOADED_FEATURES.select { |path| path.end_with?("load_fixture.rb") }
        features.should include(symlink_path)
        features.should_not include(canonical_path)
      end

      it "stores the same path that __FILE__ returns in the required file" do
        symlink_path = "#{@symlink_to_code_dir}/load_fixture_and__FILE__.rb"
        @object.require(symlink_path).should be_true
        loaded_feature = $LOADED_FEATURES.last
        ScratchPad.recorded.should == [loaded_feature]
      end

      it "requires only once when a new matching file added to path" do
        @object.require("load_fixture").should be_true
        ScratchPad.recorded.should == [:loaded]

        symlink_to_code_dir_two = tmp("codesymlinktwo")
        rm_r symlink_to_code_dir_two
        File.symlink("#{CODE_LOADING_DIR}/b", symlink_to_code_dir_two)
        begin
          $LOAD_PATH.unshift(symlink_to_code_dir_two)
          @object.require("load_fixture").should be_false
        ensure
          rm_r symlink_to_code_dir_two
        end
      end
    end

    describe "with symlinks in the required feature and $LOAD_PATH" do
      before :each do
        @dir = tmp("realdir")
        rm_r @dir
        mkdir_p @dir
        @file = "#{@dir}/realfile.rb"
        touch(@file) { |f| f.puts 'ScratchPad << __FILE__' }

        @symlink_to_dir = tmp("symdir").freeze
        rm_r @symlink_to_dir
        File.symlink(@dir, @symlink_to_dir)
        @symlink_to_file = "#{@dir}/symfile.rb"
        File.symlink("realfile.rb", @symlink_to_file)
      end

      after :each do
        rm_r @dir, @symlink_to_dir
      end

      it "canonicalizes the entry in $LOAD_PATH but not the filename passed to #require" do
        $LOAD_PATH.unshift(@symlink_to_dir)
        @object.require("symfile").should be_true
        loaded_feature = "#{@dir}/symfile.rb"
        ScratchPad.recorded.should == [loaded_feature]
        $".last.should == loaded_feature
        $LOAD_PATH[0].should == @symlink_to_dir
      end
    end
  end

  it "loads a file that recursively requires itself" do
    path = File.expand_path("recursive_require_fixture.rb", CODE_LOADING_DIR)
    -> {
      @object.require(path).should be_true
    }.should complain(/circular require considered harmful/, verbose: true)
    ScratchPad.recorded.should == [:loaded]
  end

  it "loads a file concurrently" do
    path = File.expand_path("concurrent_require_fixture.rb", CODE_LOADING_DIR)
    ScratchPad.record(@object)
    -> {
      @object.require(path)
    }.should_not complain(/circular require considered harmful/, verbose: true)
    ScratchPad.recorded.join
  end

  describe "(concurrently)" do
    before :each do
      ScratchPad.record []
      @path = File.expand_path("concurrent.rb", CODE_LOADING_DIR)
      @path2 = File.expand_path("concurrent2.rb", CODE_LOADING_DIR)
      @path3 = File.expand_path("concurrent3.rb", CODE_LOADING_DIR)
    end

    after :each do
      ScratchPad.clear
      $LOADED_FEATURES.delete @path
      $LOADED_FEATURES.delete @path2
      $LOADED_FEATURES.delete @path3
    end

    it "blocks a second thread from returning while the 1st is still requiring" do
      fin = false

      t1_res = nil
      t2_res = nil

      t2 = nil
      t1 = Thread.new do
        Thread.pass until t2
        Thread.current[:wait_for] = t2
        t1_res = @object.require(@path)
        Thread.pass until fin
        ScratchPad.recorded << :t1_post
      end

      t2 = Thread.new do
        Thread.pass until t1[:in_concurrent_rb]
        $VERBOSE, @verbose = nil, $VERBOSE
        begin
          t2_res = @object.require(@path)
          ScratchPad.recorded << :t2_post
        ensure
          $VERBOSE = @verbose
          fin = true
        end
      end

      t1.join
      t2.join

      t1_res.should be_true
      t2_res.should be_false
      ScratchPad.recorded.should == [:con_pre, :con_post, :t2_post, :t1_post]
    end

    it "blocks based on the path" do
      t1_res = nil
      t2_res = nil

      t2 = nil
      t1 = Thread.new do
        Thread.pass until t2
        Thread.current[:concurrent_require_thread] = t2
        t1_res = @object.require(@path2)
      end

      t2 = Thread.new do
        Thread.pass until t1[:in_concurrent_rb2]
        t2_res = @object.require(@path3)
      end

      t1.join
      t2.join

      t1_res.should be_true
      t2_res.should be_true
      ScratchPad.recorded.should == [:con2_pre, :con3, :con2_post]
    end

    it "allows a 2nd require if the 1st raised an exception" do
      fin = false
      t2_res = nil

      t2 = nil
      t1 = Thread.new do
        Thread.pass until t2
        Thread.current[:wait_for] = t2
        Thread.current[:con_raise] = true

        -> { @object.require(@path) }.should raise_error(RuntimeError)

        Thread.pass until fin
        ScratchPad.recorded << :t1_post
      end

      t2 = Thread.new do
        Thread.pass until t1[:in_concurrent_rb]
        $VERBOSE, @verbose = nil, $VERBOSE
        begin
          t2_res = @object.require(@path)
          ScratchPad.recorded << :t2_post
        ensure
          $VERBOSE = @verbose
          fin = true
        end
      end

      t1.join
      t2.join

      t2_res.should be_true
      ScratchPad.recorded.should == [:con_pre, :con_pre, :con_post, :t2_post, :t1_post]
    end

    it "blocks a 3rd require if the 1st raises an exception and the 2nd is still running" do
      fin = false

      t1_res = nil
      t2_res = nil

      raised = false

      t2 = nil
      t1 = Thread.new do
        Thread.current[:con_raise] = true

        -> { @object.require(@path) }.should raise_error(RuntimeError)

        raised = true
        Thread.pass until t2 && t2[:in_concurrent_rb]
        t1_res = @object.require(@path)

        Thread.pass until fin
        ScratchPad.recorded << :t1_post
      end

      t2 = Thread.new do
        Thread.pass until raised
        Thread.current[:wait_for] = t1
        begin
          t2_res = @object.require(@path)
          ScratchPad.recorded << :t2_post
        ensure
          fin = true
        end
      end

      t1.join
      t2.join

      t1_res.should be_false
      t2_res.should be_true
      ScratchPad.recorded.should == [:con_pre, :con_pre, :con_post, :t2_post, :t1_post]
    end
  end
end
