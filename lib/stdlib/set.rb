class Set
  include Enumerable

  def initialize(enum = nil)
    @hash = {}
    merge(enum) if enum
  end

  def each(&block)
    return enum_for(:each) unless block

    @hash.each_key(&block)
    self
  end

  def include?(obj)
    @hash.key?(obj)
  end

  def add(obj)
    @hash[obj] = true
    self
  end
  alias << add

  def add?(obj)
    return nil if include?(obj)

    add(obj)
  end

  def delete(obj)
    @hash.delete(obj) ? self : nil
  end

  def clear
    @hash.clear
    self
  end

  def empty?
    @hash.empty?
  end

  def size
    @hash.size
  end
  alias length size

  def to_a
    @hash.keys
  end

  def replace(enum)
    @hash.clear
    merge(enum)
  end

  def merge(enum)
    enum.each do |obj|
      add(obj)
    end
    self
  end

  def &(other)
    other = other.to_set unless other.is_a?(Set)
    result = self.class.new
    each do |obj|
      result.add(obj) if other.include?(obj)
    end
    result
  end
end

module Enumerable
  def to_set(klass = Set)
    klass.new(self)
  end
end
