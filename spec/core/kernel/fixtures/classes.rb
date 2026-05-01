module KernelSpecs
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

  class Foo
    def bar
      'done'
    end
  end
end
