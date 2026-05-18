module JSON
  def self.dump(value)
    generate(value)
  end

  def self.generate(value)
    if value.nil?
      "null"
    elsif value == true
      "true"
    elsif value == false
      "false"
    elsif value.is_a?(String)
      value.inspect
    elsif value.is_a?(Integer) || value.is_a?(Float)
      value.to_s
    elsif value.is_a?(Array)
      "[" + value.map { |item| generate(item) }.join(",") + "]"
    elsif value.is_a?(Hash)
      "{" + value.map { |key, item| generate(key.to_s) + ":" + generate(item) }.join(",") + "}"
    else
      raise TypeError, "unsupported type for JSON: #{value.class}"
    end
  end

  class Parser
    def initialize(source)
      @source = source.to_s
      @index = 0
    end

    def parse
      value = parse_value
      skip_whitespace
      raise ArgumentError, "unexpected trailing characters" if @index != @source.length

      value
    end

    private

    def parse_value
      skip_whitespace

      char = current_char
      raise ArgumentError, "unexpected end of input" if char.nil?

      if char == '"'
        parse_string
      elsif char == "["
        parse_array
      elsif char == "{"
        parse_object
      elsif char == "t"
        parse_literal("true", true)
      elsif char == "f"
        parse_literal("false", false)
      elsif char == "n"
        parse_literal("null", nil)
      else
        parse_number
      end
    end

    def parse_literal(literal, value)
      if @source[@index, literal.length] != literal
        raise ArgumentError, "invalid token"
      end

      @index += literal.length
      value
    end

    def parse_string
      raise ArgumentError, "expected string" unless current_char == '"'

      @index += 1
      out = +""

      while @index < @source.length
        char = current_char
        @index += 1

        if char == '"'
          return out
        elsif char == "\\"
          escape = current_char
          raise ArgumentError, "unterminated escape" if escape.nil?

          @index += 1
          if escape == '"' || escape == "\\" || escape == "/"
            out << escape
          elsif escape == "b"
            out << 8.chr
          elsif escape == "f"
            out << 12.chr
          elsif escape == "n"
            out << "\n"
          elsif escape == "r"
            out << "\r"
          elsif escape == "t"
            out << "\t"
          else
            raise ArgumentError, "unsupported escape"
          end
        else
          out << char
        end
      end

      raise ArgumentError, "unterminated string"
    end

    def parse_array
      @index += 1
      skip_whitespace

      array = []
      if current_char == "]"
        @index += 1
        return array
      end

      loop do
        array << parse_value
        skip_whitespace

        char = current_char
        if char == ","
          @index += 1
        elsif char == "]"
          @index += 1
          return array
        else
          raise ArgumentError, "expected ',' or ']'"
        end
      end
    end

    def parse_object
      @index += 1
      skip_whitespace

      object = {}
      if current_char == "}"
        @index += 1
        return object
      end

      loop do
        key = parse_string
        skip_whitespace
        raise ArgumentError, "expected ':'" unless current_char == ":"

        @index += 1
        object[key] = parse_value
        skip_whitespace

        char = current_char
        if char == ","
          @index += 1
          skip_whitespace
        elsif char == "}"
          @index += 1
          return object
        else
          raise ArgumentError, "expected ',' or '}'"
        end
      end
    end

    def parse_number
      start = @index
      float = false

      @index += 1 if current_char == "-"
      consume_digits

      if current_char == "."
        float = true
        @index += 1
        consume_digits
      end

      if current_char == "e" || current_char == "E"
        float = true
        @index += 1
        @index += 1 if current_char == "+" || current_char == "-"
        consume_digits
      end

      token = @source[start...@index]
      raise ArgumentError, "invalid number" if token.empty? || token == "-"

      float ? token.to_f : token.to_i
    end

    def consume_digits
      start = @index
      @index += 1 while digit?(current_char)
      raise ArgumentError, "invalid number" if start == @index
    end

    def digit?(char)
      char && char >= "0" && char <= "9"
    end

    def skip_whitespace
      while whitespace?(current_char)
        @index += 1
      end
    end

    def whitespace?(char)
      char == " " || char == "\n" || char == "\r" || char == "\t"
    end

    def current_char
      @source[@index]
    end
  end

  def self.parse(source)
    Parser.new(source).parse
  end

  class << self
    alias load parse
  end
end

class Hash
  def to_json(*)
    JSON.generate(self)
  end
end
