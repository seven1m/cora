# frozen_string_literal: true

module Zlib
  VERSION = "1.3.1" unless const_defined?(:VERSION)

  NO_FLUSH = 0 unless const_defined?(:NO_FLUSH)
  FINISH = 4 unless const_defined?(:FINISH)
  DEFAULT_COMPRESSION = -1 unless const_defined?(:DEFAULT_COMPRESSION)
  BEST_COMPRESSION = 9 unless const_defined?(:BEST_COMPRESSION)
  DEF_MEM_LEVEL = 8 unless const_defined?(:DEF_MEM_LEVEL)
  DEFAULT_STRATEGY = 0 unless const_defined?(:DEFAULT_STRATEGY)
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
    end

    def <<(string)
      ensure_open
      @buffer << String(string)
      self
    end

    def inflate(string = nil)
      self << string if string
      result = Zlib.__inflate(@buffer, Zlib.container_for_window_bits(@window_bits))
      @buffer = +""
      result
    end

    def finish
      inflate
    end

    def close
      @closed = true
      nil
    end

    private

    def ensure_open
      raise Zlib::StreamError, "stream is closed" if @closed
    end
  end

  class GzipReader
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
      @data = Zlib.__inflate(String(data || ""), GZIP)
      @position = 0
      @closed = false
    end

    def read(length = nil, outbuf = nil)
      ensure_open

      chunk = if length.nil?
        slice = @data[@position..] || +""
        @position = @data.size
        slice
      else
        raise ArgumentError, "negative length #{length} given" if length < 0
        return nil if eof?

        slice = @data[@position, length] || +""
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
      @position >= @data.size
    end

    def pos
      @position
    end

    def pos=(new_pos)
      @position = new_pos.to_i
    end

    def seek(offset, whence = IO::SEEK_SET)
      new_pos = case whence
      when IO::SEEK_SET then offset
      when IO::SEEK_CUR then @position + offset
      when IO::SEEK_END then @data.size + offset
      else raise ArgumentError, "invalid whence value: #{whence}"
      end
      @position = [[new_pos, 0].max, @data.size].min
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
      @level = level
      @buffer = +""
      @closed = false
      @mtime = nil
    end

    def write(data)
      ensure_open
      string = String(data)
      @buffer << string
      string.size
    end

    def <<(data)
      write(data)
      self
    end

    def flush
      self
    end

    def close
      return nil if @closed

      @closed = true
      @io.write(Zlib.__deflate(@buffer, @level, GZIP))
      nil
    end

    private

    def ensure_open
      raise IOError, "closed stream" if @closed
    end
  end
end
