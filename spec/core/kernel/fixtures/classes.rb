module KernelSpecs
  def self.Array_function(arg)
    Array(arg)
  end

  def self.Array_method(arg)
    Kernel.Array(arg)
  end

  def self.Hash_function(arg)
    Hash(arg)
  end

  def self.Hash_method(arg)
    Kernel.Hash(arg)
  end

  class A
    # There is Kernel#public_method, so we don't want this one to clash
    def pub_method; :public_method; end

    def undefed_method; :undefed_method; end
    undef_method :undefed_method

    protected
    def protected_method; :protected_method; end

    private
    def private_method; :private_method; end

    public
    define_method(:defined_method) { :defined }
  end

  class VisibilityChange
    class << self
      private :new
    end
  end

  class RespondViaMissing
    def respond_to_missing?(method, priv=false)
      case method
      when :handled_publicly
        true
      when :handled_privately
        priv
      when :not_handled
        false
      else
        raise "Typo in method name: #{method.inspect}"
      end
    end

    def method_missing(method, *args)
      raise "the method name should be a Symbol" unless Symbol === method
      "Done #{method}(#{args})"
    end
  end

  class PrivateToAry
    private

    def to_ary
      [1, 2]
    end

    def to_a
      [3, 4]
    end
  end

  class PrivateToA
    private

    def to_a
      [3, 4]
    end
  end

  class Foo
    def bar
      'done'
    end
  end

  module ParentMixin
    def parent_mixin_method; end
  end

  class Parent
    include ParentMixin
    def parent_method; end
    def another_parent_method; end
    def self.parent_class_method; :foo; end
  end

  class Child < Parent
    undef_method :parent_method
  end

  class Grandchild < Child
    undef_method :parent_mixin_method
  end
end
