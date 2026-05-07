module ModuleSpecs
  class NamedClass
  end

  module LookupMod
  end

  class Parent
    # For private_class_method spec
    def self.private_method; end
    private_class_method :private_method

    # For public_class_method spec
    private
    def self.public_method; end
    public_class_method :public_method
  end

  module Basic
    def public_module() end

    protected
    def protected_module() end

    private
    def private_module() end
  end

  module Super
    include Basic
  end

  module Internal
  end

  class Child < Parent
    include Super

    class << self
      include Internal
    end
  end

  module InstanceMethMod
    def bar(); :bar; end
  end

  class InstanceMeth
    include InstanceMethMod

    def foo(); :foo; end
  end

  class InstanceMethChild < InstanceMeth
  end

  module Autoload
    def self.use_ex1
      begin
        begin
          raise "test exception"
        rescue ModuleSpecs::Autoload::EX1
        end
      rescue RuntimeError
        return :good
      end
    end

    class Parent
    end

    class Child < Parent
    end

    module FromThread
      module A
        autoload :B, fixture(__FILE__, "autoload_empty.rb")

        class B
          autoload :C, fixture(__FILE__, "autoload_abc.rb")

          def self.foo
            C.foo
          end
        end
      end

      class D < A::B; end
    end
  end
end
