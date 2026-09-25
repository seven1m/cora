class Date
  class Error < ArgumentError
  end

  MONTHNAMES = [nil, "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"].each { |name| name.freeze if name }.freeze
  ABBR_MONTHNAMES = [nil, "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"].each { |name| name.freeze if name }.freeze
  DAYNAMES = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"].each(&:freeze).freeze
  ABBR_DAYNAMES = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"].each(&:freeze).freeze

  def self._parse(string, comp=true)
    result = {}
    s = string.to_str

    # MRI accepts compact time text after a civil date without parsing it as a time.
    if s =~ /\A\s*([+-]?\d{4,})-(\d{1,2})-(\d{1,2})T\d{4}Z\s*\z/
      return { year: $1.to_i, mon: $2.to_i, mday: $3.to_i }
    end

    # YYYY-MM-DD HH:MM:SS[.fraction] (ISO 8601)
    if s =~ /\A\s*([+-]?\d{4,})-(\d{1,2})-(\d{1,2})(?:[T ](\d{1,2}):(\d{2})(?::(\d{2})(?:\.(\d+))?)?([Zz]|[+-]\d{1,2}(?::?\d{2})?)?)?\s*\z/
      result[:year] = $1.to_i
      result[:mon] = $2.to_i
      result[:mday] = $3.to_i
      result[:hour] = $4.to_i if $4
      result[:min] = $5.to_i if $5
      result[:sec] = $6.to_i if $6
      result[:sec_fraction] = Rational($7) / (10 ** $7.length) if $7
      add_zone_parts(result, $8) if $8
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
    weekday_names = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday]
    weekday_re = weekday_names.join('|')
    if s =~ /\A\s*(Sun|Mon|Tue|Wed|Thu|Fri|Sat)\s+(#{month_re})\s+(\d{1,2})\s+(\d{4})\s+(\d{1,2}):(\d{2}):(\d{2})\s+GMT([+-]\d{4})\s+\([A-Za-z]+\)\s*\z/i
      result[:wday] = weekday_names.index { |name| name.start_with?($1.capitalize) }
      result[:mon] = month_names.index($2.capitalize) + 1
      result[:mday] = $3.to_i
      result[:year] = $4.to_i
      result[:hour] = $5.to_i
      result[:min] = $6.to_i
      result[:sec] = $7.to_i
      add_zone_parts(result, $8)
      result[:zone] = "GMT#{$8}"
      return result
    end
    if s =~ /\A\s*(#{weekday_re}),\s*(\d{1,2})-(#{month_re})-(\d{2})\s+(\d{1,2}):(\d{2}):(\d{2})\s+(GMT|UTC)\s*\z/i
      year = $4.to_i
      result[:wday] = weekday_names.index($1.capitalize)
      result[:mday] = $2.to_i
      result[:mon] = month_names.index($3.capitalize) + 1
      result[:year] = comp ? year + (year >= 69 ? 1900 : 2000) : year
      result[:hour] = $5.to_i
      result[:min] = $6.to_i
      result[:sec] = $7.to_i
      result[:zone] = $8.upcase
      result[:offset] = 0
      return result
    end

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

    if s =~ /\A\s*([A-Za-z]{3,})\.?(?:\s+(\d{4}))?\s*\z/
      month = month_names.index($1[0, 3].capitalize)
      if month
        result[:year] = $2.to_i if $2
        result[:mon] = month + 1
        return result
      end
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

    iso = _iso8601(s)
    iso.empty? ? result : iso
  end

  def self._strptime(string, format)
    # Minimal implementation
    unless string.respond_to?(:to_str)
      raise TypeError, "no implicit conversion of #{string.class} into String"
    end
    unless format.respond_to?(:to_str)
      raise TypeError, "no implicit conversion of #{format.class} into String"
    end
    result = {}
    s = string.to_str.dup
    f = format.to_str.dup

    while f.length > 0 && s.length > 0
      case f[0]
      when '%'
        case f[1]
        when 'Y'
          if s =~ /\A([+-]?\d{4,})/
            result[:year] = $1.to_i
            s = $'
            f = f[2..]
          elsif s =~ /\A([+-]?\d+)/
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
        when 's', 'Q'
          if s =~ /\A([+-]?\d+)/
            result[:seconds] = f[1] == 'Q' ? Rational($1.to_i, 1000) : $1.to_i
            s = $'
            f = f[2..]
          else
            return nil
          end
        when 'z'
          if s =~ /\A(Z|[+-]\d{2}(?::?\d{2}(?::?\d{2})?)?)/i
            add_zone_parts(result, $1)
            s = $'
            f = f[2..]
          else
            return nil
          end
        when ':'
          colon_count = 1
          colon_count += 1 while f[colon_count + 1] == ':'
          return result unless colon_count <= 3 && f[colon_count + 1] == 'z'
          zone_pattern = case colon_count
          when 1 then /\A([+-]\d{2}:\d{2})/
          when 2 then /\A([+-]\d{2}:\d{2}:\d{2})/
          else /\A([+-]\d{2}(?::\d{2}(?::\d{2})?)?)/
          end
          return nil unless s =~ zone_pattern
          add_zone_parts(result, $1)
          s = $'
          f = f[(colon_count + 2)..]
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
          return nil unless s[0] == '%'
          f = f[2..]
          s = s[1..]
        else
          return result
        end
      else
        if s[0] == f[0]
          s = s[1..]
          f = f[1..]
        else
          return nil
        end
      end
    end

    return nil unless f.empty?
    result[:leftover] = s unless s.empty?
    result
  end

  def self.strptime(string="-4712-01-01", format="%F", start=ITALY)
    d = _strptime(string, format)
    raise ArgumentError, "invalid date" unless d
    if d[:year] && d[:mon] && d[:mday]
      new(d[:year], d[:mon], d[:mday], start)
    end
  end

  def self._iso8601(string)
    return {} if string.nil?
    s = string.to_str
    result = {}

    if s =~ /\A([+-]?\d{4,})-?(\d{2})-?(\d{2})(?:[T ](\d{2}):(\d{2}):(\d{2})(?:[\.,](\d+))?(Z|[+-]\d{2}:?\d{2})?)?\z/
      result[:mday] = $3.to_i
      result[:year] = $1.to_i
      result[:mon] = $2.to_i
      if $4
        result[:hour] = $4.to_i
        result[:min] = $5.to_i
        result[:sec] = $6.to_i
        result[:sec_fraction] = Rational($7.to_i, 10 ** $7.length) if $7
        add_zone_parts(result, $8) if $8
      end
      return result
    end

    if s =~ /\A([+-]?\d{4,})-?(\d{3})(?:[T ](\d{2}):(\d{2}):(\d{2})(?:[\.,](\d+))?(Z|[+-]\d{2}:?\d{2})?)?\z/
      result[:year] = $1.to_i
      result[:yday] = $2.to_i
      if $3
        result[:hour] = $3.to_i
        result[:min] = $4.to_i
        result[:sec] = $5.to_i
        result[:sec_fraction] = Rational($6.to_i, 10 ** $6.length) if $6
        add_zone_parts(result, $7) if $7
      end
      return result
    end

    # MRI expands two-digit years in compact ordinal dates using the
    # 69/68 century boundary.
    if s =~ /\A(\d{2})(\d{3})\z/
      year = $1.to_i
      return { yday: $2.to_i, year: year >= 69 ? year + 1900 : year + 2000 }
    end

    if s =~ /\A([+-]?\d{4,})-?W(\d{2})(?:-?(\d))?\z/i
      result[:cwyear] = $1.to_i
      result[:cweek] = $2.to_i
      result[:cwday] = $3.to_i if $3
      return result
    end

    {}
  end

  def self._rfc3339(string)
    return {} if string.nil?
    s = string.to_str
    return {} unless s =~ /\A(\d{4})-(\d{2})-(\d{2})[Tt](\d{2}):(\d{2}):(\d{2})(?:[\.,](\d+))?(Z|[+-]\d{2}:\d{2})\z/

    result = {
      year: $1.to_i,
      mon: $2.to_i,
      mday: $3.to_i,
      hour: $4.to_i,
      min: $5.to_i,
      sec: $6.to_i
    }
    result[:sec_fraction] = Rational($7.to_i, 10 ** $7.length) if $7
    add_zone_parts(result, $8)
    result
  end

  def self.add_zone_parts(result, zone)
    result[:zone] = zone
    if zone == "Z" || zone == "z"
      result[:offset] = 0
    else
      sign = zone[0] == "-" ? -1 : 1
      digits = zone.delete(":")
      hour_digits = digits[1..]
      hours = hour_digits[0, 2].to_i
      minutes = hour_digits.length >= 4 ? hour_digits[2, 2].to_i : 0
      seconds = hour_digits.length >= 6 ? hour_digits[4, 2].to_i : 0
      result[:offset] = sign * (hours * 3600 + minutes * 60 + seconds)
    end
  end
  private_class_method :add_zone_parts

  def self.today(start=ITALY)
    time = Time.now
    new(time.year, time.month, time.day, start)
  end

  def self.ordinal(year=-4712, yday=1, start=ITALY)
    day = yday.to_int
    raise Error, "invalid date" if day == 0
    if day > 0
      date = new(year, 1, 1, start) + day - 1
      raise Error, "invalid date" unless date.year == year
    else
      date = new(year, 12, 31, start) + day + 1
      raise Error, "invalid date" unless date.year == year
    end
    date
  rescue ArgumentError
    raise Error, "invalid date"
  end

  def self.parse(string="-4712-01-01", comp=true, start=ITALY)
    unless string.respond_to?(:to_str)
      raise TypeError, "no implicit conversion of #{string.class} into String"
    end
    parts = _parse(string.to_str, comp)
    raise Error, "invalid date" if parts.empty?
    return ordinal(parts[:year], parts[:yday], start) if parts[:year] && parts[:yday]

    current = today(start)
    year = parts.fetch(:year, current.year)
    month = parts.fetch(:mon, parts[:year] ? 1 : current.month)
    day = parts.fetch(:mday, (parts[:year] || parts[:mon]) ? 1 : current.day)
    new(year, month, day, start)
  rescue ArgumentError => error
    raise error if error.is_a?(Error)
    raise Error, "invalid date"
  end

  def to_datetime
    DateTime.jd(jd, 0, 0, 0, Rational(0, 1), start)
  end

  def to_time
    date = julian? ? gregorian : self
    Time.local(date.year, date.month, date.day)
  end

  def iso8601
    strftime("%F")
  end
  alias xmlschema iso8601
  alias to_s iso8601
end

class DateTime
  def self.parse(string="-4712-01-01", comp=true, start=ITALY)
    unless string.respond_to?(:to_str)
      raise TypeError, "no implicit conversion of #{string.class} into String"
    end
    parts = _parse(string.to_str, comp)
    raise Error, "invalid date" if parts.empty?

    if parts[:year] && parts[:yday]
      ordinal_date = Date.ordinal(parts[:year], parts[:yday], start)
      parts[:mon] = ordinal_date.month
      parts[:mday] = ordinal_date.day
    end

    current = Date.today(start)
    year = parts.fetch(:year, current.year)
    month = parts.fetch(:mon, parts[:year] ? 1 : current.month)
    day = parts.fetch(:mday, (parts[:year] || parts[:mon]) ? 1 : current.day)
    second = parts.fetch(:sec, 0) + parts.fetch(:sec_fraction, 0)
    civil(year, month, day, parts.fetch(:hour, 0), parts.fetch(:min, 0), second, parts.fetch(:zone, 0), start)
  end

  def self.iso8601(string="-4712-01-01T00:00:00+00:00", start=ITALY, limit: 128)
    unless string.respond_to?(:to_str)
      raise TypeError, "no implicit conversion of #{string.class} into String"
    end
    string = string.to_str
    if limit && string.length > limit
      raise ArgumentError, "string length (#{string.length}) exceeds the limit #{limit}"
    end

    date_text, time_text = string.split("T", 2)
    if match = /\A([+-]?\d{4,})-(\d{2})-(\d{2})\z/.match(date_text)
      year, month, day = match[1].to_i, match[2].to_i, match[3].to_i
    elsif match = /\A(\d{4})(\d{2})(\d{2})\z/.match(date_text)
      year, month, day = match[1].to_i, match[2].to_i, match[3].to_i
    else
      raise Error, "invalid date"
    end

    hour = minute = second = 0
    offset = "+00:00"
    if time_text
      match = /\A(\d{2}):?(\d{2})(?::?(\d{2})(?:[.,](\d+))?)?(Z|[+-]\d{2}:?\d{2})?\z/.match(time_text)
      raise Error, "invalid date" unless match
      hour, minute = match[1].to_i, match[2].to_i
      second = match[3].to_i if match[3]
      second += Rational(match[4].to_i, 10 ** match[4].length) if match[4]
      offset = match[5] if match[5]
      offset = "+00:00" if offset == "Z"
      offset = "#{offset[0, 3]}:#{offset[3, 2]}" if offset.length == 5
    end

    civil(year, month, day, hour, minute, second, offset, start)
  end

  def iso8601(n=0)
    precision = n.to_int
    fraction = precision > 0 ? ".#{strftime("%#{precision}N")}" : ""
    "#{strftime("%FT%T")}#{fraction}#{strftime("%:z")}"
  end
  alias xmlschema iso8601
  alias to_s iso8601
end
