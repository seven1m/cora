module Etc
  def self.getlogin
    ENV["USER"] || `id -un`
  end
end
