class Pathname
  def initialize(path)
    @path = path.to_str
  end

  def to_path
    @path
  end

  alias to_s to_path

  def dirname
    Pathname.new(File.dirname(@path))
  end
end
