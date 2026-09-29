# frozen_string_literal: true

require "cora_ffi"

module FFI
  module Library
    def ffi_lib(*paths)
      @ffi_libraries = paths.map { |path| CoraFFI.open(path.nil? ? nil : path.to_s) }
    end

    def attach_function(name, *signature)
      native_name, argument_types, return_type =
        if signature.length == 2
          [name, *signature]
        elsif signature.length == 3
          signature
        else
          raise ArgumentError, "wrong number of arguments for attach_function"
        end

      libraries = @ffi_libraries || raise(LoadError, "no FFI library loaded")
      address = nil
      libraries.each do |handle|
        begin
          address = CoraFFI.symbol(handle, native_name.to_s)
          break
        rescue LoadError
        end
      end
      raise LoadError, "FFI symbol not found: #{native_name}" unless address

      types = argument_types.map(&:to_s)
      result_type = return_type.to_s
      define_singleton_method(name) do |*arguments|
        CoraFFI.call(address, result_type, types, arguments)
      end
    end
  end
end
