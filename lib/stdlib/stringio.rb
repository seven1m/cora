# frozen_string_literal: true

class StringIO
  VERSION = "3.2.0"

  RDONLY = 0 unless const_defined?(:RDONLY)
  WRONLY = 1 unless const_defined?(:WRONLY)
  RDWR = 2 unless const_defined?(:RDWR)
  APPEND = 0x8 unless const_defined?(:APPEND)
  TRUNC = 0x200 unless const_defined?(:TRUNC)
  CREAT = 0x200 unless const_defined?(:CREAT)
  EXCL = 0x400 unless const_defined?(:EXCL)

  SEEK_SET = 0 unless const_defined?(:SEEK_SET)
  SEEK_CUR = 1 unless const_defined?(:SEEK_CUR)
  SEEK_END = 2 unless const_defined?(:SEEK_END)

  attr_reader :string

  attr_accessor :lineno

  def initialize(string = nil, mode = nil, **kwargs)
    if block_given?
      warn "warning: StringIO::new() does not take block; use StringIO::open() instead"
    end

    # Validate conflicting keyword arguments
    if kwargs[:textmode] && kwargs[:binmode]
      raise ArgumentError, "both textmode and binmode specified"
    end

    raw_str = string.nil? ? +"" : String(string)
    @string = raw_str
    @pos = 0
    @lineno = 0
    @closed_read = false
    @closed_write = false
    @append_mode = false

    # Derive the effective mode string/integer (before encoding extraction)
    mode_val = kwargs[:mode] || mode

    # Parse encoding out of mode string (e.g. "w:ISO-8859-1" or "w:UTF-8:ISO-8859-1")
    mode_encoding = nil
    mode_str_base = nil
    if mode_val.is_a?(String)
      parts = mode_val.split(":")
      mode_str_base = parts[0]
      if parts.size > 1
        mode_encoding = parts[1] unless parts[1].empty?
      end
    end

    # Raise if encoding is given both in mode string and as a keyword arg
    if mode_encoding
      if kwargs[:encoding] || kwargs[:external_encoding] || kwargs[:internal_encoding]
        raise ArgumentError, "encoding specified twice"
      end
    end

    # Raise if binmode/textmode is given together with b/t mode flag
    if mode_str_base
      has_b = mode_str_base.include?("b")
      has_t = mode_str_base.include?("t")
      if has_b && (kwargs.key?(:binmode) || kwargs.key?(:textmode))
        raise ArgumentError, "binary/text mode specified twice"
      end
      if has_t && (kwargs.key?(:binmode) || kwargs.key?(:textmode))
        raise ArgumentError, "binary/text mode specified twice"
      end
    end

    # Determine base encoding: prefer explicit kwargs, else string's encoding,
    # else Encoding.default_external (for no-argument case)
    if kwargs[:external_encoding]
      @external_encoding = Encoding.find(kwargs[:external_encoding])
    elsif kwargs[:encoding]
      @external_encoding = Encoding.find(kwargs[:encoding])
    elsif mode_encoding
      @external_encoding = Encoding.find(mode_encoding)
    elsif string.nil?
      @external_encoding = Encoding.default_external
      @string = "".dup.force_encoding(@external_encoding)
    else
      @external_encoding = @string.encoding
    end

    @internal_encoding = nil
    if kwargs[:internal_encoding]
      @internal_encoding = Encoding.find(kwargs[:internal_encoding])
    end

    if kwargs[:binmode] == true
      @external_encoding = Encoding::ASCII_8BIT
    end

    # Default mode: read-only for frozen strings, read-write otherwise
    if mode_val.nil?
      mode_val = @string.frozen? ? "r" : "r+"
    end

    if mode_val.is_a?(Integer)
      parse_mode_integer!(mode_val)
      return
    end

    mode_str = mode_str_base || String(mode_val)

    # Validate frozen string with write modes
    if @string.frozen?
      if mode_str.start_with?("w") || mode_str.start_with?("a") || mode_str.include?("+")
        raise Errno::EACCES, "Permission denied"
      end
    end

    parse_mode_string!(mode_str)
  end

  def self.allocate
    obj = super
    obj.instance_variable_set(:@string, +"")
    obj.instance_variable_set(:@pos, 0)
    obj.instance_variable_set(:@lineno, 0)
    obj.instance_variable_set(:@closed_read, false)
    obj.instance_variable_set(:@closed_write, false)
    obj.instance_variable_set(:@append_mode, false)
    obj.instance_variable_set(:@external_encoding, Encoding::UTF_8)
    obj.instance_variable_set(:@internal_encoding, nil)
    obj
  end

  def self.open(string = +"", mode = "r", **kwargs)
    io = new(string, mode, **kwargs)
    if block_given?
      begin
        yield(io)
      ensure
        io.close
      end
    else
      io
    end
  end

  def string=(value)
    @string = String(value)
    @pos = 0
    @lineno = 0
    value
  end

  def pos
    @pos
  end

  def pos=(offset)
    offset = offset.to_i
    if offset < 0
      raise Errno::EINVAL, "Invalid argument"
    end
    @pos = offset
    offset
  end

  alias tell pos

  def seek(offset, whence = SEEK_SET)
    begin
      offset = offset.to_int
    rescue NoMethodError
      raise TypeError, "no implicit conversion of #{offset.class} into Integer"
    end
    case whence
    when SEEK_SET
      new_pos = offset
    when SEEK_CUR
      new_pos = @pos + offset
    when SEEK_END
      new_pos = @string.bytesize + offset
    else
      raise Errno::EINVAL, "Invalid argument"
    end
    if new_pos < 0
      raise Errno::EINVAL, "Invalid argument"
    end
    @pos = new_pos
    0
  end

  def rewind
    @pos = 0
    @lineno = 0
    0
  end

  def closed_read?
    @closed_read
  end

  def closed_write?
    @closed_write
  end

  def close
    @closed_read = true
    @closed_write = true
    nil
  end

  def close_read
    @closed_read = true
    nil
  end

  def close_write
    @closed_write = true
    nil
  end

  def external_encoding
    @external_encoding
  end

  def internal_encoding
    @internal_encoding
  end

  def set_encoding(enc)
    @external_encoding = Encoding.find(enc)
    self
  end

  def read(length = nil, outbuf = nil)
    if @closed_read
      raise IOError, "not opened for reading"
    end

    if length.nil?
      result = @string[@pos, @string.bytesize - @pos]
      @pos = @string.bytesize
      if outbuf
        begin
          outbuf_str = outbuf.to_str
        rescue NoMethodError
          raise TypeError, "no implicit conversion of #{outbuf.class} into String"
        end
        saved_enc = outbuf_str.encoding
        begin
          outbuf_str.replace(result)
        rescue NoMethodError
          raise TypeError, "undefined method 'replace' for #{outbuf_str.class}"
        end
        outbuf_str.force_encoding(saved_enc)
        return outbuf_str
      end
      result
    else
      begin
        length = length.to_int
      rescue NoMethodError
        raise TypeError, "no implicit conversion of #{length.class} into Integer"
      end

      if length < 0
        raise ArgumentError, "negative length #{length} given"
      end

      if @pos >= @string.bytesize
        return nil
      end

      avail = @string.bytesize - @pos
      actual_len = length < avail ? length : avail

      result = @string[@pos, actual_len]
      @pos += actual_len

      # read(length) always returns a binary (ASCII-8BIT) string
      result = result.b if result.encoding != Encoding::ASCII_8BIT

      if outbuf
        begin
          outbuf_str = outbuf.to_str
        rescue NoMethodError
          raise TypeError, "no implicit conversion of #{outbuf.class} into String"
        end
        saved_enc = outbuf_str.encoding
        begin
          outbuf_str.replace(result)
        rescue NoMethodError
          raise TypeError, "undefined method 'replace' for #{outbuf_str.class}"
        end
        outbuf_str.force_encoding(saved_enc)
        return outbuf_str
      end
      result
    end
  end

  def write(string)
    if @closed_write
      raise IOError, "not opened for writing"
    end

    string = String(string)

    # Transcode if external encoding is set and neither encoding is BINARY
    if @external_encoding != Encoding::ASCII_8BIT &&
       string.encoding != Encoding::ASCII_8BIT &&
       @external_encoding != string.encoding
      string = string.encode(@external_encoding)
    end

    return 0 if string.bytesize == 0

    # In binary mode, ensure both @string and the write data are binary
    if @external_encoding == Encoding::ASCII_8BIT
      @string.force_encoding(Encoding::ASCII_8BIT) if @string.encoding != Encoding::ASCII_8BIT
      string = string.b if string.encoding != Encoding::ASCII_8BIT
    end

    if @append_mode
      @pos = @string.bytesize
    end

    if @pos > @string.bytesize
      @string += "\x00" * (@pos - @string.bytesize)
    end

    if @pos < @string.bytesize
      @string[@pos, string.bytesize] = string
    else
      @string += string
    end

    @pos += string.bytesize
    string.bytesize
  end

  alias << write

  def print(*args)
    if @closed_write
      raise IOError, "not opened for writing"
    end

    sep = $\ || "\n"
    str = args.map { |arg| String(arg) }.join(sep)
    write(str)
    nil
  end

  def puts(*args)
    if @closed_write
      raise IOError, "not opened for writing"
    end

    if args.empty?
      write("\n")
    else
      args.each do |arg|
        s = String(arg)
        s += "\n" unless s.end_with?("\n")
        write(s)
      end
    end
    nil
  end

  def getc
    if @closed_read
      raise IOError, "not opened for reading"
    end

    if @pos >= @string.bytesize
      return nil
    end

    ch = @string.getbyte(@pos)
    @pos += 1
    ch.chr
  end

  def ungetc(char)
    if @closed_read
      raise IOError, "not opened for reading"
    end

    char = char.to_i.chr
    if @pos > 0
      @pos -= 1
      @string.setbyte(@pos, char.getbyte(0))
    end
    nil
  end

  def readbyte
    if @closed_read
      raise IOError, "not opened for reading"
    end

    if @pos >= @string.bytesize
      raise EOFError, "end of file reached"
    end

    b = @string.getbyte(@pos)
    @pos += 1
    b
  end

  def size
    @string.bytesize
  end

  alias length size

  def binmode
    @external_encoding = Encoding::ASCII_8BIT
    self
  end

  def eof?
    @pos >= @string.bytesize
  end

  private

  def parse_mode_string!(mode_str)
    mode_str = String(mode_str)

    @append_mode = false

    if mode_str.start_with?("r")
      @closed_read = false
      @closed_write = true
    elsif mode_str.start_with?("w")
      @closed_read = true
      @closed_write = false
      orig_enc = @string.encoding
      @string = "".dup.force_encoding(orig_enc)
    elsif mode_str.start_with?("a")
      @closed_read = true
      @closed_write = false
      @append_mode = true
    end

    if mode_str.include?("+")
      @closed_read = false
      @closed_write = false
    end

    if mode_str.include?("b")
      @external_encoding = Encoding::ASCII_8BIT
    end
  end

  def parse_mode_integer!(mode_int)
    # Validate frozen string with write modes
    accmode = mode_int & 3
    is_write = accmode == WRONLY || accmode == RDWR
    is_trunc = (mode_int & IO::TRUNC) == IO::TRUNC

    if @string.frozen? && is_trunc
      raise FrozenError, "can't modify frozen String: #{@string.inspect}"
    end
    if @string.frozen? && is_write
      raise Errno::EACCES, "Permission denied"
    end

    if accmode == RDONLY
      @closed_read = false
      @closed_write = true
    elsif accmode == WRONLY
      @closed_read = true
      @closed_write = false
    elsif accmode == RDWR
      @closed_read = false
      @closed_write = false
    end

    if is_trunc
      orig_enc = @string.encoding
      @string = "".dup.force_encoding(orig_enc)
    end

    if (mode_int & IO::APPEND) == IO::APPEND
      @append_mode = true
    end
  end
end
