require_relative '../../spec_helper'

describe "Dir.mkdir" do
  it "creates the named directory with the given permissions" do
    base = tmp('dir_mkdir_permissions')
    nonexisting = "#{base}/nonexisting"
    default_perms = "#{base}/default_perms"
    reduced = "#{base}/reduced"
    always_returns_0 = "#{base}/always_returns_0"
    rm_r(base)
    mkdir_p(base)
    begin
      File.should_not.exist?(nonexisting)
      Dir.mkdir nonexisting
      File.should.exist?(nonexisting)
      platform_is_not :windows do
        Dir.mkdir default_perms
        a = File.stat(default_perms).mode
        Dir.mkdir reduced, (a - 1)
        File.stat(reduced).mode.should_not == a
      end
      platform_is :windows do
        Dir.mkdir default_perms, 0666
        a = File.stat(default_perms).mode
        Dir.mkdir reduced, 0444
        File.stat(reduced).mode.should_not == a
      end

      Dir.mkdir(always_returns_0).should == 0
      platform_is_not(:windows) do
        File.chmod(0777, nonexisting, default_perms, reduced, always_returns_0)
      end
      platform_is_not(:windows) do
        File.chmod(0644, nonexisting, default_perms, reduced, always_returns_0)
      end
    ensure
      rm_r(base)
    end
  end

  it "calls #to_path on non-String path arguments" do
    p = mock('path')
    path = tmp('dir_mkdir_to_path')
    p.should_receive(:to_path).and_return(path)
    rm_r(path)
    begin
      Dir.mkdir(p)
    ensure
      rm_r(path)
    end
  end

  it "calls #to_int on non-Integer permissions argument" do
    path = tmp('dir_mkdir_to_int')
    permissions = mock('permissions')
    permissions.should_receive(:to_int).and_return(0666)
    rm_r(path)
    begin
      Dir.mkdir(path, permissions)
    ensure
      rm_r(path)
    end
  end

  it "raises TypeError if non-Integer permissions argument does not have #to_int method" do
    base = tmp('dir_mkdir_type_error')
    path = "#{base}/nonexisting"
    permissions = Object.new

    rm_r(base)
    mkdir_p(base)
    begin
      -> { Dir.mkdir(path, permissions) }.should raise_error(TypeError, 'no implicit conversion of Object into Integer')
    ensure
      rm_r(base)
    end
  end

  it "raises a SystemCallError if any of the directories in the path before the last does not exist" do
    path = "#{tmp('dir_mkdir_missing_parent')}/missing/subdir"
    rm_r("#{tmp('dir_mkdir_missing_parent')}")
    -> { Dir.mkdir(path) }.should raise_error(SystemCallError)
  end

  it "raises Errno::EEXIST if the specified directory already exists" do
    path = tmp('dir_mkdir_existing_dir')
    rm_r(path)
    mkdir_p(path)
    begin
      -> { Dir.mkdir(path) }.should raise_error(Errno::EEXIST)
    ensure
      rm_r(path)
    end
  end

  it "raises Errno::EEXIST if the argument points to the existing file" do
    path = tmp('dir_mkdir_existing_file')
    rm_r(path)
    touch(path)
    begin
      -> { Dir.mkdir(path) }.should raise_error(Errno::EEXIST)
    ensure
      rm_r(path)
    end
  end
end

# The permissions flag are not supported on Windows as stated in documentation:
# The permissions may be modified by the value of File.umask, and are ignored on NT.
platform_is_not :windows do
  CORAFIXME "as_user, SystemCallError, and File.chmod are not implemented yet for Dir.mkdir permission errors", exception: NoMethodError, message: /undefined method 'as_user'/ do
    as_user do
      describe "Dir.mkdir" do
        before :each do
          @dir = tmp "noperms"
        end

        after :each do
          File.chmod 0777, @dir
          rm_r @dir
        end

        it "raises a SystemCallError when lacking adequate permissions in the parent dir" do
          Dir.mkdir @dir, 0000

          -> { Dir.mkdir "#{@dir}/subdir" }.should raise_error(SystemCallError)
        end
      end
    end
  end
end
