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
end
