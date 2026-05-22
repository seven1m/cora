class Date
  def self._parse(string, comp=true)
    result = {}
    s = string.to_s

    # YYYY-MM-DD HH:MM:SS[.fraction] (ISO 8601)
    if s =~ /\A\s*(\d{4})-(\d{1,2})-(\d{1,2})(?:[T ](\d{1,2}):(\d{2})(?::(\d{2})(?:\.(\d+))?)?)?\s*\z/
      result[:year] = $1.to_i
      result[:mon] = $2.to_i
      result[:mday] = $3.to_i
      result[:hour] = $4.to_i if $4
      result[:min] = $5.to_i if $5
      result[:sec] = $6.to_i if $6
      result[:sec_fraction] = Rational($7) / (10 ** $7.length) if $7
      return result
    end

    # YYYY/MM/DD HH:MM:SS
    if s =~ /\A\s*(\d{4})\/(\d{1,2})\/(\d{1,2})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?\s*\z/
      result[:year] = $1.to_i
      result[:mon] = $2.to_i
      result[:mday] = $3.to_i
      result[:hour] = $4.to_i if $4
      result[:min] = $5.to_i if $5
      result[:sec] = $6.to_i if $6
      return result
    end

    # DD Mon YYYY HH:MM:SS or Mon DD HH:MM:SS YYYY
    month_names = %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec]
    month_re = month_names.join('|')
    if s =~ /\A\s*(\d{1,2})\s+(#{month_re})\s+(\d{4})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?\s*\z/i
      result[:mday] = $1.to_i
      result[:mon] = month_names.index($2.capitalize) + 1
      result[:year] = $3.to_i
      result[:hour] = $4.to_i if $4
      result[:min] = $5.to_i if $5
      result[:sec] = $6.to_i if $6
      return result
    end
    if s =~ /\A\s*(#{month_re})\s+(\d{1,2})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?\s+(\d{4})\s*\z/i
      result[:mon] = month_names.index($1.capitalize) + 1
      result[:mday] = $2.to_i
      result[:hour] = $3.to_i if $3
      result[:min] = $4.to_i if $4
      result[:sec] = $5.to_i if $5
      result[:year] = $6.to_i
      return result
    end

    # MM/DD/YY or DD/MM/YY
    # ...

    # HH:MM:SS alone
    if s =~ /\A\s*(\d{1,2}):(\d{2})(?::(\d{2})(?:\.(\d+))?)?\s*\z/
      result[:hour] = $1.to_i
      result[:min] = $2.to_i
      result[:sec] = $3.to_i if $3
      result[:sec_fraction] = Rational($4) / (10 ** $4.length) if $4
      return result
    end

    # RFC 2822: "Mon, DD YYYY HH:MM:SS ZONE" or "DD Mon YYYY HH:MM:SS ZONE"
    if s =~ /\A\s*(?:\w+,\s*)?(\d{1,2})\s+(#{month_re})\s+(\d{4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s+([+-]\d{4}|[A-Z]{1,5})\s*\z/i
      result[:mday] = $1.to_i
      result[:mon] = month_names.index($2.capitalize) + 1
      result[:year] = $3.to_i
      result[:hour] = $4.to_i
      result[:min] = $5.to_i
      result[:sec] = $6.to_i if $6
      result[:zone] = $7
      return result
    end

    result
  end

  def self._strptime(string, format)
    # Minimal implementation
    result = {}
    s = string.to_s.dup
    f = format.dup

    while f.length > 0 && s.length > 0
      case f[0]
      when '%'
        case f[1]
        when 'Y'
          if s =~ /\A(\d{4})/
            result[:year] = $1.to_i
            s = $'
            f = f[2..]
          elsif s =~ /\A(\d+)/
            result[:year] = $1.to_i
            s = $'
            f = f[2..]
          else
            return nil
          end
        when 'm'
          if s =~ /\A(\d{1,2})/
            result[:mon] = $1.to_i
            s = $'
            f = f[2..]
          else
            return nil
          end
        when 'd'
          if s =~ /\A(\d{1,2})/
            result[:mday] = $1.to_i
            s = $'
            f = f[2..]
          else
            return nil
          end
        when 'H'
          if s =~ /\A(\d{1,2})/
            result[:hour] = $1.to_i
            s = $'
            f = f[2..]
          else
            return nil
          end
        when 'M'
          if s =~ /\A(\d{2})/
            result[:min] = $1.to_i
            s = $'
            f = f[2..]
          else
            return nil
          end
        when 'S'
          if s =~ /\A(\d{2})/
            result[:sec] = $1.to_i
            s = $'
            f = f[2..]
          else
            return nil
          end
        when 'z'
          if s =~ /\A([+-]\d{4})/
            result[:zone] = $1
            s = $'
            f = f[2..]
          else
            return nil
          end
        when 'Z'
          if s =~ /\A([A-Z]{1,5})/
            result[:zone] = $1
            s = $'
            f = f[2..]
          else
            # optional
            f = f[2..]
          end
        when 'F' # %Y-%m-%d
          f = '%Y-%m-%d' + f[2..]
        when 'T' # %H:%M:%S
          f = '%H:%M:%S' + f[2..]
        when '%'
          f = f[2..]
          s = s[1..]
        else
          f = f[1..]
        end
      else
        if s[0] == f[0]
          s = s[1..]
          f = f[1..]
        else
          break
        end
      end
    end

    result
  end

  def self.strptime(string, format)
    d = _strptime(string, format)
    raise ArgumentError, "invalid date" unless d
    if d[:year] && d[:mon] && d[:mday]
      new(d[:year], d[:mon], d[:mday])
    end
  end
end