# frozen_string_literal: true

require "openssl"

module Digest
  class Base < OpenSSL::Digest
    class << self
      def digest(data)
        new(data).digest
      end

      def hexdigest(data)
        new(data).hexdigest
      end

      def base64digest(data)
        new(data).base64digest
      end
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
