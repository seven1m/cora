class StringScanner
  class Error < StandardError
  end

  Version = "0.1.0"
  Id = "$Id$"

  attr_reader :string, :pos
  alias pointer pos

  def self.must_C_version
    self
  end

  def initialize(string, options = nil, fixed_anchor: false)
    @string = String(string)
    @fixed_anchor = fixed_anchor ? true : false
    @pos = 0
    @last_match = nil
  end

  def inspect
    return "#<#{self.class} fin>" if eos?

    head = @string.byteslice(0, @pos)
    tail = @string.byteslice(@pos, 5)
    head = head.bytesize > 5 ? "..." + head.byteslice(-5, 5) : head
    tail = tail.nil? ? "" : tail
    suffix = @pos + 5 < @string.bytesize ? "..." : ""
    "#<#{self.class} #{@pos}/#{@string.bytesize} #{head.inspect} @ #{(tail + suffix).inspect}>"
  end

  def fixed_anchor?
    @fixed_anchor
  end

  def string=(other_string)
    @string = String(other_string)
    @pos = 0
    @last_match = nil
    other_string
  end

  def concat(other_string)
    @string << String(other_string)
    self
  end
  alias << concat

  def pos=(new_pos)
    new_pos = new_pos.to_i
    new_pos += @string.bytesize if new_pos < 0
    raise RangeError, "index out of range" if new_pos < 0 || new_pos > @string.bytesize

    @pos = new_pos
  end
  alias pointer= pos=

  def charpos
    @string.byteslice(0, @pos).length
  end

  def reset
    @pos = 0
    @last_match = nil
    self
  end

  def terminate
    @pos = @string.bytesize
    @last_match = nil
    self
  end

  def unscan
    raise Error, "unscan failed: previous match record not exist" unless @last_match

    @pos = @last_match.begin(0)
    @last_match = nil
    self
  end

  def beginning_of_line?
    @pos == 0 || @string.byteslice(@pos - 1, 1) == "\n"
  end
  alias bol? beginning_of_line?

  def eos?
    @pos >= @string.bytesize
  end

  def rest?
    !eos?
  end

  def rest
    @string.byteslice(@pos, @string.bytesize)
  end

  def rest_size
    @string.bytesize - @pos
  end

  def matched?
    !@last_match.nil?
  end

  def matched
    @last_match ? @last_match[0] : nil
  end

  def matched_size
    @last_match ? @last_match[0].bytesize : nil
  end

  def [](group)
    @last_match ? @last_match[group] : nil
  end

  def values_at(*groups)
    return nil unless @last_match

    groups.map { |group| @last_match[group] }
  end

  def captures
    @last_match ? @last_match.captures : nil
  end

  def size
    @last_match ? @last_match.size : nil
  end

  def pre_match
    @last_match ? @last_match.pre_match : nil
  end

  def post_match
    @last_match ? @last_match.post_match : nil
  end

  def named_captures
    @last_match ? @last_match.named_captures : {}
  end

  def peek(length)
    raise ArgumentError, "negative string size (or size too big)" if length < 0

    @string.byteslice(@pos, length)
  end

  def peek_byte
    @string.getbyte(@pos)
  end

  def get_byte
    return nil if eos?

    byte = @string.byteslice(@pos, 1)
    @last_match = literal_regexp(byte).match(@string, @pos)
    @pos += 1
    byte
  end

  def scan_byte
    return nil if eos?

    value = @string.getbyte(@pos)
    get_byte
    value
  end

  def getch
    scan(/./m)
  end

  def scan_integer(base: 10)
    case base
    when 10
      value = scan(/[+-]?\d+/)
      value ? value.to_i : nil
    when 16
      value = scan(/[+-]?(0x)?[0-9a-fA-F]+/)
      value ? value.to_i(16) : nil
    else
      raise ArgumentError, "Unsupported integer base: #{base.inspect}, expected 10 or 16"
    end
  end

  def check(pattern)
    scan_common(pattern, false, true)
  end

  def scan(pattern)
    scan_common(pattern, true, true)
  end

  def match?(pattern)
    scan_common(pattern, false, false)
  end

  def skip(pattern)
    scan_common(pattern, true, false)
  end

  def scan_full(pattern, advance_pointer, return_string)
    if advance_pointer
      return_string ? scan(pattern) : skip(pattern)
    else
      return_string ? check(pattern) : match?(pattern)
    end
  end

  def check_until(pattern)
    search_common(pattern, false, true)
  end

  def scan_until(pattern)
    search_common(pattern, true, true)
  end

  def exist?(pattern)
    search_common(pattern, false, false)
  end

  def skip_until(pattern)
    search_common(pattern, true, false)
  end

  def search_full(pattern, advance_pointer, return_string)
    if advance_pointer
      return_string ? scan_until(pattern) : skip_until(pattern)
    else
      return_string ? check_until(pattern) : exist?(pattern)
    end
  end

  private

  def scan_common(pattern, advance_pointer, return_string)
    match = match_at_current_position(pattern)
    unless match
      @last_match = nil
      return nil
    end

    @last_match = match
    width = match[0].bytesize
    @pos += width if advance_pointer
    return_string ? match[0] : width
  end

  def search_common(pattern, advance_pointer, return_string)
    match = search_from_current_position(pattern)
    unless match
      @last_match = nil
      return nil
    end

    @last_match = match
    finish = match.begin(0) + match[0].bytesize
    length = finish - @pos
    @pos = finish if advance_pointer
    return_string ? @string.byteslice(@pos - (advance_pointer ? length : 0), length) : length
  end

  def match_at_current_position(pattern)
    match = to_regexp(pattern).match(@string, @pos)
    return nil unless match && match.begin(0) == @pos

    match
  end

  def search_from_current_position(pattern)
    to_regexp(pattern).match(@string, @pos)
  end

  def to_regexp(pattern)
    return pattern if pattern.is_a?(Regexp)

    literal_regexp(String(pattern))
  end

  def literal_regexp(string)
    Regexp.new(escape_regexp(string))
  end

  def escape_regexp(string)
    escaped = +""
    specials = "^$\\.|?*+()[]{}"
    string.each_char do |char|
      escaped << "\\" if specials.include?(char)
      escaped << char
    end
    escaped
  end
end
