# frozen_string_literal: true

require "openssl"

def Digest(name)
  Digest.const_get(name)
end

module Digest
  module Instance
    def update(string)
      raise RuntimeError, "#{self.class} does not implement update()"
    end
    alias << update

    def new
      clone.reset
    end

    def hexdigest(*args)
      digest(*args).unpack1("H*")
    end

    def digest!
      result = digest
      reset
      result
    end

    def ==(other)
      if Instance === other
        left, right = digest, other.digest
      else
        left = hexdigest
        right = String.try_convert(other)
        return false if right.nil?
      end
      left = String.try_convert(left) or raise TypeError, "no implicit conversion into String"
      right = String.try_convert(right) or raise TypeError, "no implicit conversion into String"
      left == right
    end

    def inspect
      "#<#{self.class}: #{hexdigest}>"
    end

    def to_s
      hexdigest
    end

    def length
      digest_length
    end
    alias size length

    def base64digest(*args)
      [digest(*args)].pack("m0")
    end
  end

  class Base < OpenSSL::Digest
    include Instance
    define_method :update, OpenSSL::Digest.instance_method(:update)
    alias << update
    class << self
      def file(name, *args)
        new(*args).file(name)
      end

      def digest(data, *args)
        new(*args).digest(data)
      end

      def hexdigest(data, *args)
        new(*args).hexdigest(data)
      end

      def base64digest(data, *args)
        new(*args).base64digest(data)
      end
    end

    def file(name)
      File.open(name, "rb") do |input|
        while (chunk = input.read(16_384))
          update(chunk)
        end
      end
      self
    end
  end

  class MD5 < Base
    def initialize(data = nil)
      data.nil? ? super("MD5") : super("MD5", data)
    end
  end

  class SHA1 < Base
    def initialize(data = nil)
      data.nil? ? super("SHA1") : super("SHA1", data)
    end
  end

  class SHA2 < Base
    def initialize(bit_length = 256)
      algorithm = case bit_length
      when 256 then "SHA256"
      when 384 then "SHA384"
      when 512 then "SHA512"
      else
        raise ArgumentError, "unsupported bit length: #{bit_length}"
      end
      super(algorithm)
    end
  end

  class SHA256 < Base
    def initialize(data = nil)
      data.nil? ? super("SHA256") : super("SHA256", data)
    end
  end

  class SHA384 < Base
    def initialize(data = nil)
      data.nil? ? super("SHA384") : super("SHA384", data)
    end
  end

  class SHA512 < Base
    def initialize(data = nil)
      data.nil? ? super("SHA512") : super("SHA512", data)
    end
  end
end
