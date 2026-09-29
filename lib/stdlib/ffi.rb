# frozen_string_literal: true

require "cora_ffi"

module FFI
  class Pointer
    attr_reader :address

    def initialize(address)
      @address = address
    end

    def to_i
      @address
    end

    def read_string(length = nil)
      CoraFFI.read(@address, length)
    end

    def write_string(string, length = string.bytesize)
      CoraFFI.write(@address, string, length)
      self
    end

    def put_char(offset, byte)
      CoraFFI.put_char(@address, offset, byte)
      self
    end
  end

  class MemoryPointer < Pointer
    def self.new(*args)
      pointer = super(*args)
      return pointer unless block_given?

      begin
        yield pointer
      ensure
        pointer.free
      end
    end

    def initialize(type, count = nil, clear = true)
      size = case type
             when Integer then type
             when :char then 1
             else raise ArgumentError, "unsupported FFI allocation type: #{type}"
             end
      super(CoraFFI.alloc(size * (count || 1), clear))
    end

    def free
      return if @address.nil?

      CoraFFI.free(@address)
      @address = nil
    end
  end

  module Library
    def ffi_lib(*paths)
      @ffi_libraries = paths.map { |path| CoraFFI.open(path.nil? ? nil : path.to_s) }
    end

    def callback(name, argument_types, return_type)
      (@ffi_callbacks ||= {})[name.to_sym] = [argument_types, return_type]
    end

    def enum(name, entries)
      values = {}
      next_value = 0
      index = 0
      while index < entries.length
        entry = entries[index]
        raise ArgumentError, "expected an enum name" unless entry.is_a?(Symbol)

        if entries[index + 1].is_a?(Integer)
          next_value = entries[index + 1]
          index += 1
        end
        values[entry] = next_value
        next_value += 1
        index += 1
      end
      (@ffi_enums ||= {})[name.to_sym] = values
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

      callbacks = @ffi_callbacks || {}
      enums = @ffi_enums || {}
      types = argument_types.map { |type| callbacks.key?(type) ? "pointer" : enums.key?(type) ? "int" : type.to_s }
      result_type = enums.key?(return_type) ? "int" : return_type.to_s
      result_enum = enums[return_type]
      define_singleton_method(name) do |*arguments|
        converted = arguments.each_with_index.map do |argument, index|
          type = argument_types[index]
          if callbacks.key?(type)
            raise NotImplementedError, "FFI callback calls are not implemented"
          elsif (mapping = enums[type])
            argument.is_a?(Symbol) ? mapping.fetch(argument) : argument
          elsif argument.is_a?(FFI::Pointer)
            argument.address
          else
            argument
          end
        end
        result = CoraFFI.call(address, result_type, types, converted)
        if result_enum
          result_enum.key(result)
        elsif return_type == :pointer
          FFI::Pointer.new(result || 0)
        else
          result
        end
      end
    end
  end
end
