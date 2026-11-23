class Pathname
  include Comparable
  def self.glob(pattern, flags = 0, base: nil, &block)
    paths = Dir.glob(pattern, flags, base: base).map { |path| new(path) }
    return paths unless block

    paths.each(&block)
    nil
  end

  def glob(pattern, flags = 0, &block)
    paths = Dir.glob(pattern, flags, base: @path).map do |path|
      self.class.new(File.join(@path, path))
    end
    return paths unless block

    paths.each(&block)
    nil
  end

  def self.getwd
    new(Dir.getwd)
  end

  class << self
    alias pwd getwd
  end

  def initialize(path)
    @path = File.path(path).dup
  end

  def to_path
    @path
  end

  alias to_s to_path

  def to_str
    @path
  end

  def ==(other)
    other.is_a?(Pathname) && @path == other.to_path
  end

  alias eql? ==
  alias === ==

  def <=>(other)
    return nil unless other.is_a?(Pathname)

    @path.tr(File::SEPARATOR, "\0") <=> other.to_path.tr(File::SEPARATOR, "\0")
  end

  def hash
    @path.hash
  end

  def inspect
    "#<Pathname:#{@path}>"
  end

  def dirname
    Pathname.new(File.dirname(@path))
  end

  def basename(*args)
    Pathname.new(File.basename(@path, *args))
  end

  def expand_path(directory = nil)
    Pathname.new(File.expand_path(@path, directory))
  end

  def parent
    dirname
  end

  def ascend
    return to_enum(__method__) unless block_given?

    path = @path
    yield self
    loop do
      basename = File.basename(path)
      break if basename == File::SEPARATOR

      basename_start = path.rindex(basename)
      break unless basename_start

      path = path[0...basename_start]
      break if path.empty?

      parent = path.sub(%r{/+\z}, "")
      parent = File::SEPARATOR if parent.empty?
      yield self.class.new(parent)
    end
    nil
  end

  def join(*args)
    return self if args.empty?

    result = args.pop
    result = Pathname.new(result) unless result.is_a?(Pathname)
    return result if result.absolute?

    args.reverse_each do |path|
      path = Pathname.new(path) unless path.is_a?(Pathname)
      result = path + result
      return result if result.absolute?
    end
    self + result
  end

  def +(other)
    suffix = other.is_a?(Pathname) ? other.to_path : Pathname.new(other).to_path
    return Pathname.new(suffix) if suffix.start_with?(File::SEPARATOR)

    base = normalize_join_base(@path)
    loop do
      if suffix == "." || suffix.start_with?("./")
        suffix = suffix == "." ? "" : suffix[2..]
      elsif suffix == ".." || suffix.start_with?("../")
        break if base.empty? || File.basename(base) == ".."

        base = normalize_join_base(File.dirname(base)) unless base.match?(/\A\/+\z/)
        suffix = suffix == ".." ? "" : suffix[3..]
      else
        break
      end
      suffix = suffix.sub(/\A\/+/, "")
    end
    path = if suffix.empty?
      base.empty? ? "." : base
    elsif base.empty?
      suffix
    else
      File.join(base, suffix)
    end
    Pathname.new(path)
  end
  alias / +

  def exist?
    File.exist?(@path)
  end

  def file?
    File.file?(@path)
  end

  def directory?
    File.directory?(@path)
  end

  def symlink?
    File.symlink?(@path)
  end

  def readable?
    File.readable?(@path)
  end

  def owned?
    File.owned?(@path)
  end

  def writable?
    File.writable?(@path)
  end

  def executable?
    File.executable?(@path)
  end

  def empty?
    directory? ? Dir.empty?(@path) : File.zero?(@path)
  end

  def birthtime
    stat.birthtime
  end

  def size
    File.size(@path)
  end

  def size?
    File.size?(@path)
  end

  def zero?
    File.zero?(@path)
  end

  def ftype
    File.ftype(@path)
  end

  def stat
    File.stat(@path)
  end

  def lstat
    File.lstat(@path)
  end

  def children
    Dir.children(@path).map { |child| Pathname.new(File.join(@path, child)) }
  end

  def each_child(&block)
    children.each(&block)
  end

  def absolute?
    @path.start_with?("/")
  end

  def relative?
    !absolute?
  end

  def root?
    @path == "/"
  end

  def realpath(basedir = nil)
    Pathname.new(File.realpath(@path, basedir))
  end

  def realdirpath(basedir = nil)
    Pathname.new(File.realdirpath(@path, basedir))
  end

  def sub(pattern, replacement = nil, &block)
    if replacement
      Pathname.new(@path.sub(pattern, replacement))
    elsif block
      Pathname.new(@path.sub(pattern, &block))
    else
      raise ArgumentError, "wrong number of arguments (given 1, expected 2)"
    end
  end

  def open(*args, &block)
    File.open(@path, *args, &block)
  end

  def read(*args)
    File.read(@path, *args)
  end

  def binread(*args)
    File.binread(@path, *args)
  end

  def write(*args)
    File.write(@path, *args)
  end

  def binwrite(*args)
    File.binwrite(@path, *args)
  end

  def relative_path_from(base)
    base = Pathname.new(base) unless base.is_a?(Pathname)
    raise ArgumentError, "different prefix" unless absolute? == base.absolute?

    destination = clean_components(@path)
    origin = clean_components(base.to_path)
    while !destination.empty? && !origin.empty? && destination.first == origin.first
      destination.shift
      origin.shift
    end
    raise ArgumentError, "base_directory has .." if origin.include?("..")

    components = Array.new(origin.length, "..") + destination
    Pathname.new(components.empty? ? "." : components.join(File::SEPARATOR))
  end

  private

  def normalize_join_base(path)
    path = path.sub(/\/+\z/, "") unless path.match?(/\A\/+\z/)
    while File.basename(path) == "."
      parent = File.dirname(path)
      return "" if parent == path

      path = parent
    end
    path
  end

  def clean_components(path)
    components = []
    absolute = path.start_with?(File::SEPARATOR)
    path.split(File::SEPARATOR).each do |part|
      case part
      when "", "."
        next
      when ".."
        if !components.empty? && components.last != ".."
          components.pop
        elsif !absolute
          components << part
        end
      else
        components << part
      end
    end
    components
  end

end

module Kernel
  def Pathname(path)
    path.is_a?(::Pathname) ? path : ::Pathname.new(path)
  end

  module_function :Pathname
end
