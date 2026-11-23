# frozen_string_literal: true

require "digest"

module Digest
  def self.bubblebabble(string)
    string = String.try_convert(string) or raise TypeError, "no implicit conversion into String"
    vowels = "aeiouy"
    consonants = "bcdfghklmnprstvzx"
    output = "x".b
    seed = 1
    index = 0
    loop do
      if index >= string.bytesize
        output << vowels[seed % 6] << consonants[16] << vowels[seed / 6]
        break
      end
      first = string.getbyte(index)
      index += 1
      output << vowels[(((first >> 6) & 3) + seed) % 6]
      output << consonants[(first >> 2) & 15]
      output << vowels[((first & 3) + seed / 6) % 6]
      break if index >= string.bytesize
      second = string.getbyte(index)
      index += 1
      output << consonants[(second >> 4) & 15] << "-" << consonants[second & 15]
      seed = (seed * 5 + first * 7 + second) % 36
    end
    output << "x"
  end

  module Instance
    def bubblebabble
      Digest.bubblebabble(digest)
    end
  end

  class Base
    def self.bubblebabble(data, *args)
      Digest.bubblebabble(digest(data, *args))
    end
  end
end
