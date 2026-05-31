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
end
