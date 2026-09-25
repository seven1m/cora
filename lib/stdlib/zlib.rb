# frozen_string_literal: true

module Zlib
  VERSION = "1.3.1" unless const_defined?(:VERSION)

  NO_FLUSH = 0 unless const_defined?(:NO_FLUSH)
  FINISH = 4 unless const_defined?(:FINISH)
  DEFAULT_COMPRESSION = -1 unless const_defined?(:DEFAULT_COMPRESSION)
  NO_COMPRESSION = 0 unless const_defined?(:NO_COMPRESSION)
  BEST_SPEED = 1 unless const_defined?(:BEST_SPEED)
  BEST_COMPRESSION = 9 unless const_defined?(:BEST_COMPRESSION)
  DEF_MEM_LEVEL = 8 unless const_defined?(:DEF_MEM_LEVEL)
  DEFAULT_STRATEGY = 0 unless const_defined?(:DEFAULT_STRATEGY)
  FILTERED = 1 unless const_defined?(:FILTERED)
  HUFFMAN_ONLY = 2 unless const_defined?(:HUFFMAN_ONLY)
  MAX_WBITS = 15 unless const_defined?(:MAX_WBITS)

  RAW = 0
  GZIP = 1
  ZLIB = 2
  AUTO = 3

  class Error < StandardError; end unless const_defined?(:Error)
  class StreamError < Error; end unless const_defined?(:StreamError)
  class DataError < Error; end unless const_defined?(:DataError)
  class BufError < Error; end unless const_defined?(:BufError)

  class GzipFile
    class Error < Zlib::Error; end unless const_defined?(:Error)
    class CRCError < Error; end unless const_defined?(:CRCError)
    class LengthError < Error; end unless const_defined?(:LengthError)
  end

  def self.container_for_window_bits(window_bits)
    return AUTO if window_bits >= MAX_WBITS + 32
    return GZIP if window_bits >= MAX_WBITS + 16
    return RAW if window_bits < 0

    ZLIB
  end

  class Deflate
    def self.deflate(data, level = DEFAULT_COMPRESSION)
      Zlib.__deflate(String(data), level, ZLIB)
    end

    def initialize(level = DEFAULT_COMPRESSION, window_bits = MAX_WBITS, *_rest)
      @level = level
      @window_bits = window_bits
      @buffer = +""
      @closed = false
    end

    def <<(string)
      ensure_open
      @buffer << String(string)
      self
    end

    def deflate(string = nil, flush = NO_FLUSH)
      self << string if string
      flush == FINISH ? finish : +""
    end

    def finish
      ensure_open
      @closed = true
      Zlib.__deflate(@buffer, @level, Zlib.container_for_window_bits(@window_bits))
    end

    def close
      finish unless @closed
      nil
    end

    private

    def ensure_open
      raise Zlib::StreamError, "stream is closed" if @closed
    end
  end

  class Inflate
    def self.inflate(data)
      Zlib.__inflate(String(data), ZLIB)
    end

    def initialize(window_bits = MAX_WBITS)
      @window_bits = window_bits
      @buffer = +""
      @closed = false
      @delivered = 0
    end

    def <<(string)
      ensure_open
      @buffer << String(string)
      self
    end

    def inflate(string = nil)
      self << string if string
      begin
        result = Zlib.__inflate(@buffer, Zlib.container_for_window_bits(@window_bits))
        result = result.byteslice(@delivered, result.bytesize - @delivered) || +""
        @buffer = +""
        @delivered = 0
        result
      rescue Zlib::DataError
        parsed = inflate_stored_gzip
        raise unless parsed

        result = parsed.byteslice(@delivered, parsed.bytesize - @delivered) || +""
        @delivered = parsed.bytesize
        result
      end
    end

    def finish
      return +"" if @buffer.empty?

      begin
        result = Zlib.__inflate(@buffer, Zlib.container_for_window_bits(@window_bits))
      rescue Zlib::DataError
        result = inflate_stored_gzip
        raise unless result
      end
      result = result.byteslice(@delivered, result.bytesize - @delivered) || +""
      @buffer = +""
      @delivered = 0
      result
    end

    def close
      @closed = true
      nil
    end

    private

    def ensure_open
      raise Zlib::StreamError, "stream is closed" if @closed
    end

    def inflate_stored_gzip
      return nil unless @window_bits >= MAX_WBITS + 16
      return +"" if @buffer.bytesize < 10
      return nil unless @buffer.getbyte(0) == 0x1f && @buffer.getbyte(1) == 0x8b

      output = +"".b
      offset = 10
      while offset < @buffer.bytesize
        header = @buffer.getbyte(offset)
        return nil unless ((header >> 1) & 3).zero?
        return output if offset + 5 > @buffer.bytesize

        length = @buffer.getbyte(offset + 1) | (@buffer.getbyte(offset + 2) << 8)
        inverse = @buffer.getbyte(offset + 3) | (@buffer.getbyte(offset + 4) << 8)
        return nil unless (length ^ inverse) == 0xffff
        return output if offset + 5 + length > @buffer.bytesize

        output << @buffer.byteslice(offset + 5, length)
        offset += 5 + length
        break if (header & 1) == 1
      end
      output
    end
  end

  class GzipReader
    attr_reader :level

    def self.wrap(io, *args, **kwargs)
      reader = new(io, *args, **kwargs)
      return reader unless block_given?

      begin
        yield reader
      ensure
        reader.close
      end
    end

    def initialize(io, **_kwargs)
      @io = io
      data = io.read
      @mtime = Time.at(data.byteslice(4, 4).unpack1("V"))
      @level = case data.getbyte(8)
               when 4 then BEST_SPEED
               when 2 then BEST_COMPRESSION
               else DEFAULT_COMPRESSION
               end
      @data = Zlib.__inflate(String(data || ""), GZIP)
      @data_len = @data.bytesize
      @position = 0
      @closed = false
    end

    def read(length = nil, outbuf = nil)
      ensure_open

      chunk = if length.nil?
        slice = @data.byteslice(@position, @data_len - @position) || +""
        @position = @data_len
        slice
      else
        raise ArgumentError, "negative length #{length} given" if length < 0
        return nil if eof?

        slice = @data.byteslice(@position, length) || +""
        @position += slice.size
        slice
      end

      if outbuf
        outbuf.replace(chunk)
      else
        chunk
      end
    end

    def eof?
      @position >= @data_len
    end

    def pos
      @position
    end

    def pos=(new_pos)
      @position = new_pos.to_i
    end

    attr_reader :mtime

    def seek(offset, whence = IO::SEEK_SET)
      new_pos = case whence
      when IO::SEEK_SET then offset
      when IO::SEEK_CUR then @position + offset
      when IO::SEEK_END then @data_len + offset
      else raise ArgumentError, "invalid whence value: #{whence}"
      end
      @position = [[new_pos, 0].max, @data_len].min
      0
    end

    def getc
      return nil if eof?
      c = @data.getbyte(@position)
      @position += 1
      c
    end

    def close
      return nil if @closed

      @closed = true
      @position = @data.size
      nil
    end

    private

    def ensure_open
      raise IOError, "closed stream" if @closed
    end
  end

  class GzipWriter
    attr_accessor :mtime
    attr_reader :level

    def self.wrap(io, *args)
      writer = new(io, *args)
      return writer unless block_given?

      begin
        yield writer
      ensure
        writer.close
      end
    end

    def initialize(io, level = DEFAULT_COMPRESSION, *_rest)
      @io = io
      @level = level.nil? ? DEFAULT_COMPRESSION : level
      @buffer = +""
      @closed = false
      @mtime = nil
      @emitted = false
      @crc = 0
      @size = 0
      @failed = false
    end

    def write(data)
      ensure_open
      string = String(data)
      @buffer << string
      @crc = Zlib.crc32(string, @crc)
      @size = (@size + string.bytesize) & 0xffffffff
      string.size
    end

    def <<(data)
      write(data)
      self
    end

    def flush(*_args)
      ensure_open
      begin
        output = +"".b
        output << gzip_header unless @emitted
        output << stored_blocks(@buffer, false)
        @io.write(output)
        @buffer.clear
      rescue Exception
        @failed = true
        raise
      end
      self
    end


    def finish
      ensure_open

      if @failed
        @closed = true
        return @io
      end

      if @emitted
        @io.write(stored_blocks(@buffer, true) << [@crc, @size].pack("V2"))
      else
        compressed = Zlib.__deflate(@buffer, @level, GZIP)
        timestamp = (@mtime || Time.now).to_i
        compressed.setbyte(4, timestamp & 0xff)
        compressed.setbyte(5, (timestamp >> 8) & 0xff)
        compressed.setbyte(6, (timestamp >> 16) & 0xff)
        compressed.setbyte(7, (timestamp >> 24) & 0xff)
        compressed.setbyte(8, gzip_xfl)
        @io.write(compressed)
      end

      @buffer.clear
      @closed = true
      @io
    end

    def close
      finish unless @closed
      @io.close
      @io
    end

    private

    def ensure_open
      raise Zlib::GzipFile::Error, "closed gzip stream" if @closed
    end

    def gzip_header
      timestamp = (@mtime || Time.now).to_i
      @emitted = true
      [0x1f, 0x8b, 8, 0, timestamp, gzip_xfl, 255].pack("C4VC2")
    end

    def gzip_xfl
      return 4 if @level == BEST_SPEED
      return 2 if @level == BEST_COMPRESSION

      0
    end

    def stored_blocks(data, final)
      output = +"".b
      if data.empty?
        output << [final ? 1 : 0, 0, 0, 0xff, 0xff].pack("C*") if final
        return output
      end

      offset = 0
      while offset < data.bytesize
        length = [data.bytesize - offset, 65_535].min
        last = final && offset + length == data.bytesize
        output << [last ? 1 : 0, length, length ^ 0xffff].pack("Cvv")
        output << data.byteslice(offset, length)
        offset += length
      end
      output
    end
  end
end
