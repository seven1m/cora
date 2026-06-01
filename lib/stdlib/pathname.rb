class Pathname
  def initialize(path)
    @path = path.to_str
  end

  def to_path
    @path
  end

  alias to_s to_path

  def to_str
    @path
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

  def join(*args)
    Pathname.new(File.join(@path, *args))
  end

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

  def writable?
    File.writable?(@path)
  end

  def executable?
    File.executable?(@path)
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

  def relative_path_from(base)
    base = base.to_s if base.is_a?(Pathname)
    base = base.to_str

    # Split paths into components
    src_parts = @path.sub(/\/+\z/, "").split("/")
    dst_parts = base.sub(/\/+\z/, "").split("/")

    # Remove common prefix
    common = 0
    while common < src_parts.length && common < dst_parts.length && src_parts[common] == dst_parts[common]
      common += 1
    end

    # Build result: "../" for each remaining component in base, then remaining in path
    result = []
    (dst_parts.length - common).times { result << ".." }
    src_parts[common..].each { |part| result << part }

    result = result.join("/")
    result = "." if result.empty?
    Pathname.new(result)
  end
end
