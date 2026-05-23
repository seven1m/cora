# frozen_string_literal: true

require "random/formatter"

module SecureRandom
  VERSION = "0.1.0" unless const_defined?(:VERSION)

  class << self
    private

    def gen_random(n)
      bytes = Random.urandom(n)
      unless bytes && bytes.bytesize == n
        raise NotImplementedError, "No random device"
      end
      bytes
    end

    public :gen_random
  end
end

SecureRandom.extend(Random::Formatter)
