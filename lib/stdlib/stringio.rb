# frozen_string_literal: true

class StringIO
  include Enumerable
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

  def sync
    true
  end

  def sync=(value)
    value
  end

  def initialize(string = nil, mode = nil, **kwargs)
    if block_given?
      warn "warning: StringIO::new() does not take block; use StringIO::open() instead"
    end

    # Validate conflicting keyword arguments
    if kwargs[:textmode] && kwargs[:binmode]
      raise ArgumentError, "both textmode and binmode specified"
    end

    raw_str = string.nil? ? +"" : (String.try_convert(string) || raise(TypeError, "no implicit conversion into String"))
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
      @external_encoding = nil
    else
      @external_encoding = nil
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
      @readable = !@closed_read
      @writable = !@closed_write
      return self
    end

    mode_str = mode_str_base || String(mode_val)

    # Validate frozen string with write modes
    if @string.frozen?
      if mode_str.start_with?("w") || mode_str.start_with?("a") || mode_str.include?("+")
        raise Errno::EACCES, "Permission denied"
      end
    end

    parse_mode_string!(mode_str)
    @readable = !@closed_read
    @writable = !@closed_write
    self
  end

  def self.allocate
    obj = super
    obj.instance_variable_set(:@string, +"")
    obj.instance_variable_set(:@pos, 0)
    obj.instance_variable_set(:@lineno, 0)
    obj.instance_variable_set(:@closed_read, false)
    obj.instance_variable_set(:@closed_write, false)
    obj.instance_variable_set(:@append_mode, false)
    obj.instance_variable_set(:@readable, true)
    obj.instance_variable_set(:@writable, true)
    obj.instance_variable_set(:@external_encoding, Encoding::UTF_8)
    obj.instance_variable_set(:@internal_encoding, nil)
    obj
  end

  def self.open(string = +"", mode = nil, **kwargs)
    io = new(string, mode, **kwargs)
    if block_given?
      begin
        yield(io)
      ensure
        io.close
        io.instance_variable_set(:@string, nil)
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
    raise IOError, "closed stream" if closed?
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

  def closed?
    @closed_read && @closed_write
  end

  def close
    @closed_read = true
    @closed_write = true
    nil
  end

  def close_read
    raise IOError, "not opened for reading" unless @readable
    @closed_read = true
    nil
  end

  def close_write
    raise IOError, "not opened for writing" unless @writable
    @closed_write = true
    nil
  end

  def external_encoding
    @external_encoding || @string.encoding
  end

  def internal_encoding
    @internal_encoding
  end

  def set_encoding(enc, internal = nil, **options)
    @external_encoding = Encoding.find(enc)
    @string.force_encoding(@external_encoding) unless @string.frozen?
    self
  end

  def read(length = nil, outbuf = nil)
    raise IOError, "not opened for reading" if @closed_read
    unless length.nil?
      length = Integer.try_convert(length) || raise(TypeError, "no implicit conversion into Integer")
      raise ArgumentError, "negative length #{length} given" if length < 0
    end
    buffer = outbuf.nil? ? nil : String.try_convert(outbuf)
    raise TypeError, "no implicit conversion into String" if !outbuf.nil? && buffer.nil?
    raise FrozenError, "can't modify frozen String" if buffer && buffer.frozen?
    available = [@string.bytesize - @pos, 0].max
    count = length.nil? ? available : [length, available].min
    result = (@string.byteslice(@pos, count) || +"").dup
    result.force_encoding(length.nil? ? external_encoding : Encoding::ASCII_8BIT)
    @pos += count
    if buffer
      encoding = buffer.encoding
      buffer.replace(result).force_encoding(encoding)
    end
    return nil if length && length > 0 && available == 0
    buffer || result
  end

  def sysread(length = nil, outbuf = nil)
    result = read(length, outbuf)
    raise EOFError, "end of file reached" if result.nil?
    result
  end

  alias readpartial sysread

  def read_nonblock(length = nil, outbuf = nil, exception: true)
    result = read(length, outbuf)
    raise EOFError, "end of file reached" if result.nil? && exception
    result
  end

  def gets(separator = $/, limit = nil, chomp: false)
    if @closed_read
      raise IOError, "not opened for reading"
    end

    if limit.nil? && !separator.nil? && !separator.respond_to?(:to_str)
      limit = separator.to_int
      separator = $/
    else
      separator = separator.to_str unless separator.nil?
      limit = limit.to_int unless limit.nil?
    end

    if limit == 0
      $_ = "".dup.force_encoding(@string.encoding)
      return $_
    end

    return nil if @pos >= @string.bytesize

    available = @string.bytesize - @pos
    length = available

    unless separator.nil?
      record_separator = separator.empty? ? "\n\n" : separator
      unless Encoding.compatible?(@string, record_separator)
        raise Encoding::CompatibilityError, "incompatible character encodings"
      end
      separator_pos = @string.b.index(record_separator.b, @pos)
      if separator_pos
        separator_end = separator_pos + record_separator.bytesize
        if separator.empty?
          separator_end += 1 while @string.byteslice(separator_end, 1) == "\n"
        end
        length = separator_end - @pos
      end
    end

    if limit && limit > 0 && limit < length
      boundary = 0
      @string.byteslice(@pos, length).each_char do |char|
        boundary += char.bytesize
        break if boundary >= limit
      end
      length = boundary
    end
    result = @string.byteslice(@pos, length)
    @pos += result.bytesize
    @lineno += 1

    result = separator.nil? ? result.chomp : result.chomp(separator) if chomp
    $_ = result
  end

  def each_line(separator = $/, limit = nil, chomp: false)
    if limit.nil? && !separator.nil? && !separator.respond_to?(:to_str)
      limit = separator.to_int
      separator = $/
    else
      separator = separator.to_str unless separator.nil?
      limit = limit.to_int unless limit.nil?
    end

    unless block_given?
      return Enumerator.new do |yielder|
        each_line(separator, limit, chomp: chomp) { |line| yielder << line }
      end
    end

    raise ArgumentError, "invalid limit: 0" if limit == 0
    previous_last_line = $_
    begin
      while line = gets(separator, limit, chomp: chomp)
        yield line
      end
    ensure
      $_ = previous_last_line
    end
    self
  end

  alias each each_line

  def truncate(length)
    raise IOError, "not opened for writing" if @closed_write
    unless length.is_a?(Integer)
      raise TypeError, "no implicit conversion into Integer" unless length.respond_to?(:to_int, true)
      length = length.__send__(:to_int)
      raise TypeError, "to_int did not return Integer" unless length.is_a?(Integer)
    end
    raise Errno::EINVAL, "Invalid argument" if length < 0

    encoding = @string.encoding
    @string.force_encoding(Encoding::ASCII_8BIT)
    begin
      if length < @string.bytesize
        @string.slice!(length, @string.bytesize - length)
      elsif length > @string.bytesize
        @string.concat("\x00" * (length - @string.bytesize))
      end
    ensure
      @string.force_encoding(encoding)
    end
    length
  end

  def write(*strings)
    strings.inject(0) { |total, string| total + write_string(string) }
  end

  def write_string(string)
    if @closed_write
      raise IOError, "not opened for writing"
    end

    string = string.to_s

    # Transcode if external encoding is set and neither encoding is BINARY
    if external_encoding != Encoding::ASCII_8BIT &&
       string.encoding != Encoding::ASCII_8BIT &&
       external_encoding != string.encoding
      string = string.encode(external_encoding)
    end

    return 0 if string.bytesize == 0

    # In binary mode, ensure both @string and the write data are binary
    if external_encoding == Encoding::ASCII_8BIT
      @string.force_encoding(Encoding::ASCII_8BIT) if @string.encoding != Encoding::ASCII_8BIT
      string = string.b if string.encoding != Encoding::ASCII_8BIT
    end

    if @append_mode
      @pos = @string.bytesize
    end

    encoding = @string.encoding
    @string.force_encoding(Encoding::ASCII_8BIT)
    begin
      if @pos > @string.bytesize
        @string.concat("\x00" * (@pos - @string.bytesize))
      end

      if @pos < @string.bytesize
        @string[@pos, string.bytesize] = string.b
      else
        @string.concat(string.b)
      end
    ensure
      @string.force_encoding(encoding)
    end

    @pos += string.bytesize
    string.bytesize
  end

  private :write_string

  def <<(value)
    write(value)
    self
  end

  alias syswrite write

  def write_nonblock(value, exception: true)
    write(value)
  end

  def flush
    self
  end

  def printf(*args)
    write(sprintf(*args))
    nil
  end

  def ungetc(char)
    raise IOError, "not opened for reading" if @closed_read
    return nil if char.nil?
    bytes = char.is_a?(Integer) ? char.chr(external_encoding) : String.try_convert(char)
    raise TypeError, "no implicit conversion into String" unless bytes
    pushback(bytes)
  end

  def ungetbyte(byte)
    raise IOError, "not opened for reading" if @closed_read
    return nil if byte.nil?
    bytes = byte.is_a?(String) ? byte : ((Integer.try_convert(byte) || raise(TypeError, "no implicit conversion into Integer")) & 255).chr
    pushback(bytes)
  end

  def pushback(bytes)
    encoding = @string.encoding
    @string.force_encoding(Encoding::ASCII_8BIT)
    begin
      @string.concat("\x00" * (@pos - @string.bytesize)) if @pos > @string.bytesize
      start = [@pos - bytes.bytesize, 0].max
      @string[start, @pos - start] = bytes.b
      @pos = start
    ensure
      @string.force_encoding(encoding)
    end
    nil
  end
  private :pushback

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

  alias eof eof?

  def each_byte
    return enum_for(:each_byte) unless block_given?
    while byte = getbyte
      yield byte
    end
    self
  end

  def each_char
    return enum_for(:each_char) unless block_given?
    while char = getc
      yield char
    end
    self
  end

  def each_codepoint
    return enum_for(:each_codepoint) unless block_given?
    each_char { |char| yield char.ord }
    self
  end

  def readchar
    getc || raise(EOFError, "end of file reached")
  end

  def readline(*args, **kwargs)
    gets(*args, **kwargs) || raise(EOFError, "end of file reached")
  end

  def readlines(*args, **kwargs)
    each_line(*args, **kwargs).to_a
  end

  def putc(value)
    bytes = value.is_a?(String) ? value.byteslice(0, 1) : ((Integer.try_convert(value) || raise(TypeError, "no implicit conversion into Integer")) & 255).chr
    write(bytes.b)
    value
  end

  def fcntl(*args)
    raise NotImplementedError, "fcntl is not implemented"
  end

  def fileno
    nil
  end
  alias pid fileno

  def fsync
    0
  end

  def reopen(*args)
    if args.empty?
      @pos = @lineno = 0
      @closed_read = @closed_write = false
      @readable = @writable = true
      @append_mode = false
    elsif args.size == 1 && !args[0].is_a?(String)
      other = args[0]
      unless other.is_a?(StringIO)
        raise TypeError, "no implicit conversion into StringIO" unless other.respond_to?(:to_strio, true)
        other = other.__send__(:to_strio)
        raise TypeError, "to_strio did not return StringIO" unless other.is_a?(StringIO)
      end
      other.instance_variables.each { |name| instance_variable_set(name, other.instance_variable_get(name)) }
    else
      initialize(*args)
    end
    self
  end

  def set_encoding_by_bom
    raise FrozenError, "can't modify frozen StringIO" if frozen?
    return nil if @closed_read
    [["\x00\x00\xFE\xFF".b, Encoding::UTF_32BE],
     ["\xFF\xFE\x00\x00".b, Encoding::UTF_32LE],
     ["\xEF\xBB\xBF".b, Encoding::UTF_8],
     ["\xFE\xFF".b, Encoding::UTF_16BE],
     ["\xFF\xFE".b, Encoding::UTF_16LE]].each do |bytes, encoding|
      if @string.byteslice(@pos, bytes.bytesize)&.b == bytes
        @pos += bytes.bytesize
        set_encoding(encoding)
        return encoding
      end
    end
    nil
  end

  private

  def instance_variables_to_inspect
    []
  end

  def parse_mode_string!(mode_str)
    mode_str = String(mode_str)

    @append_mode = false

    if mode_str.start_with?("r")
      @closed_read = false
      @closed_write = true
    elsif mode_str.start_with?("w")
      @closed_read = true
      @closed_write = false
      @string.clear
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
      @string.clear
    end

    if (mode_int & IO::APPEND) == IO::APPEND
      @append_mode = true
    end
  end
end
