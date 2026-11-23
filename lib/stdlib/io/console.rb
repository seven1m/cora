# frozen_string_literal: true
require 'stringio'

class StringIO
  def getch(**options)
    getc
  end

  def getpass(prompt = nil)
    $stderr.print(prompt) if prompt
    gets&.chomp
  end
end
