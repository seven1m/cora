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

    SUPPORTED_CIPHERS = [
      "AES-128-CBC",
      "AES-192-CBC",
      "AES-256-CBC"
    ].freeze

    attr_reader :name

    def self.ciphers
      SUPPORTED_CIPHERS.dup
    end

    def initialize(name)
      @name = String(name).upcase
      unless SUPPORTED_CIPHERS.include?(@name)
        raise CipherError, "unsupported cipher algorithm (#{name})"
      end
    end
  end

  module SSL
    VERIFY_NONE = 0 unless const_defined?(:VERIFY_NONE)
    VERIFY_PEER = 1 unless const_defined?(:VERIFY_PEER)

    class SSLError < OpenSSL::OpenSSLError; end unless const_defined?(:SSLError)

    class SSLContext
      SESSION_CACHE_CLIENT = 0x0001 unless const_defined?(:SESSION_CACHE_CLIENT)
      SESSION_CACHE_NO_INTERNAL_STORE = 0x0200 unless const_defined?(:SESSION_CACHE_NO_INTERNAL_STORE)

      DEFAULT_PARAMS = {
        verify_mode: OpenSSL::SSL::VERIFY_PEER,
        verify_hostname: true
      }.freeze

      attr_accessor :ca_file, :ca_path, :cert, :cert_store, :ciphers,
        :extra_chain_cert, :key, :ssl_timeout, :ssl_version, :min_version,
        :max_version, :verify_callback, :verify_depth, :verify_mode,
        :verify_hostname, :session_cache_mode, :session_new_cb

      def initialize(version = nil)
        self.ssl_version = version if version
        self.verify_mode = OpenSSL::SSL::VERIFY_NONE
        self.verify_hostname = false
      end

      def set_params(params = {})
        params = DEFAULT_PARAMS.merge(params)
        params.each { |name, value| public_send("#{name}=", value) }
        if verify_mode != OpenSSL::SSL::VERIFY_NONE && !ca_file && !ca_path && !cert_store
          store = OpenSSL::X509::Store.new
          store.set_default_paths
          self.cert_store = store
        end
        params
      end
    end

    class SSLSocket
      attr_accessor :sync_close, :hostname, :session
      attr_reader :context

      def initialize(io, context = SSLContext.new)
        @io = io
        @context = context
        @sync_close = false
        @hostname = nil
        @session = nil
        @__ssl_native = nil
        @__ssl_closed = false
      end

      def connect
        OpenSSL.__ssl_socket_connect(self, false, true)
        self
      end

      def connect_nonblock(exception: true)
        OpenSSL.__ssl_socket_connect(self, true, exception)
      end

      def read_nonblock(length, buffer = nil, exception: true)
        OpenSSL.__ssl_socket_read_nonblock(self, length, buffer, exception)
      end

      def write_nonblock(string, exception: true)
        OpenSSL.__ssl_socket_write_nonblock(self, string, exception)
      end

      def post_connection_check(hostname)
        OpenSSL.__ssl_socket_post_connection_check(self, hostname)
      end

      def ssl_version
        OpenSSL.__ssl_socket_ssl_version(self)
      end

      def cipher
        OpenSSL.__ssl_socket_cipher(self)
      end

      def peer_cert
        pem = OpenSSL.__ssl_socket_peer_cert_pem(self)
        pem ? OpenSSL::X509::Certificate.new(pem) : nil
      end

      def eof?
        OpenSSL.__ssl_socket_eof(self)
      end

      def close
        return nil if @__ssl_closed

        OpenSSL.__ssl_socket_close(self)
        @__ssl_closed = true
        @io.close if sync_close && !@io.closed?
        nil
      end

      def closed?
        @__ssl_closed
      end

      def setsockopt(*args)
        @io.setsockopt(*args)
      end

      def to_io
        @io
      end
    end
  end

  module X509
    V_ERR_CERT_HAS_EXPIRED = 10 unless const_defined?(:V_ERR_CERT_HAS_EXPIRED)
    V_ERR_CERT_NOT_YET_VALID = 9 unless const_defined?(:V_ERR_CERT_NOT_YET_VALID)
    V_ERR_CERT_REJECTED = 28 unless const_defined?(:V_ERR_CERT_REJECTED)
    V_ERR_CERT_UNTRUSTED = 27 unless const_defined?(:V_ERR_CERT_UNTRUSTED)
    V_ERR_DEPTH_ZERO_SELF_SIGNED_CERT = 18 unless const_defined?(:V_ERR_DEPTH_ZERO_SELF_SIGNED_CERT)
    V_ERR_INVALID_CA = 24 unless const_defined?(:V_ERR_INVALID_CA)
    V_ERR_INVALID_PURPOSE = 26 unless const_defined?(:V_ERR_INVALID_PURPOSE)
    V_ERR_SELF_SIGNED_CERT_IN_CHAIN = 19 unless const_defined?(:V_ERR_SELF_SIGNED_CERT_IN_CHAIN)
    V_ERR_UNABLE_TO_GET_ISSUER_CERT_LOCALLY = 20 unless const_defined?(:V_ERR_UNABLE_TO_GET_ISSUER_CERT_LOCALLY)
    V_ERR_UNABLE_TO_VERIFY_LEAF_SIGNATURE = 21 unless const_defined?(:V_ERR_UNABLE_TO_VERIFY_LEAF_SIGNATURE)

    class NameError < OpenSSL::OpenSSLError; end

    class Store
      attr_reader :files, :paths

      def initialize
        @files = []
        @paths = []
        @set_default_paths = false
      end

      def set_default_paths
        @set_default_paths = true
        self
      end

      def add_file(path)
        @files << String(path)
        self
      end

      def add_path(path)
        @paths << String(path)
        self
      end
    end

    class Certificate
      attr_reader :pem

      def initialize(pem)
        @pem = String(pem)
      end
    end

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

  module PKey
    class PKeyError < OpenSSL::OpenSSLError; end unless const_defined?(:PKeyError)

    class RSA
      attr_reader :pem

      def initialize(pem)
        @pem = String(pem)
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
