class Pathname
  def initialize(path)
    @path = path.to_str
  end

  def to_path
    @path
  end

  alias to_s to_path
end
