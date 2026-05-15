# frozen_string_literal: true

module OpenSSL
  VERSION = "4.0.1" unless const_defined?(:VERSION)
  OPENSSL_VERSION = "OpenSSL 3.0.0 Cora" unless const_defined?(:OPENSSL_VERSION)
  OPENSSL_VERSION_NUMBER = 0x30000000 unless const_defined?(:OPENSSL_VERSION_NUMBER)

  def self.secure_compare(a, b)
    hashed_a = OpenSSL::Digest.digest("SHA256", a)
    hashed_b = OpenSSL::Digest.digest("SHA256", b)
    OpenSSL.fixed_length_secure_compare(hashed_a, hashed_b) && a == b
  end

  module Random
    class RandomError < OpenSSL::OpenSSLError; end unless const_defined?(:RandomError)
  end

  module ASN1
    IA5STRING = 22 unless const_defined?(:IA5STRING)
    UTF8STRING = 12 unless const_defined?(:UTF8STRING)
  end

  class Cipher
    class CipherError < OpenSSL::OpenSSLError; end unless const_defined?(:CipherError)
  end

  module X509
    class NameError < OpenSSL::OpenSSLError; end

    class Name
      VALID_TYPES = {
        "C" => OpenSSL::ASN1::UTF8STRING,
        "CN" => OpenSSL::ASN1::UTF8STRING,
        "DC" => OpenSSL::ASN1::IA5STRING,
        "L" => OpenSSL::ASN1::UTF8STRING,
        "O" => OpenSSL::ASN1::UTF8STRING,
        "OU" => OpenSSL::ASN1::UTF8STRING,
        "ST" => OpenSSL::ASN1::UTF8STRING
      }.freeze

      def self.parse(distinguished_name)
        string = String(distinguished_name)
        parts = if string.start_with?("/")
          string.split("/").reject(&:empty?)
        else
          string.split(",").map(&:strip).reject(&:empty?)
        end

        raise TypeError, "invalid X509 name" if parts.empty?

        entries = parts.map do |part|
          key, value = part.split("=", 2)
          raise TypeError, "invalid X509 name" if key.nil? || value.nil?

          object_type = VALID_TYPES[key]
          raise ::OpenSSL::X509::NameError, "invalid field name: #{key}" if object_type.nil?

          [key, value, object_type]
        end

        new(entries)
      end

      def initialize(entries)
        @entries = entries.map(&:dup)
      end

      def to_s
        "/" + @entries.map { |key, value, _type| "#{key}=#{value}" }.join("/")
      end

      def to_a
        @entries.map(&:dup)
      end
    end
  end

  class Digest::SHA1 < Digest
    def initialize(data = nil)
      data.nil? ? super("SHA1") : super("SHA1", data)
    end
  end

  class Digest::SHA256 < Digest
    def initialize(data = nil)
      data.nil? ? super("SHA256") : super("SHA256", data)
    end
  end

  class Digest::SHA384 < Digest
    def initialize(data = nil)
      data.nil? ? super("SHA384") : super("SHA384", data)
    end
  end

  class Digest::SHA512 < Digest
    def initialize(data = nil)
      data.nil? ? super("SHA512") : super("SHA512", data)
    end
  end
end
