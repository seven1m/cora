class Set
  include Enumerable

  def self.[](*objects)
    new(objects)
  end

  def initialize(enum = nil, &block)
    @hash = {}
    if block && enum
      enum.each { |object| add(block.call(object)) }
    elsif enum
      merge(enum)
    end
  end

  def each(&block)
    return enum_for(:each) unless block

    @hash.each_key(&block)
    self
  end

  def include?(obj)
    @hash.key?(obj)
  end
  alias member? include?

  def compare_by_identity
    raise FrozenError, "can't modify frozen Set: Set[]" if frozen?

    @hash.compare_by_identity
    self
  end

  def compare_by_identity?
    @hash.compare_by_identity?
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

  def hash
    @hash.hash
  end

  def ==(other)
    other.is_a?(Set) &&
      compare_by_identity? == other.compare_by_identity? &&
      size == other.size &&
      all? { |object| other.include?(object) }
  end
  alias eql? ==

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
  def to_set(*args, &block)
    raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 0..1)" if args.size > 1

    unless args.empty?
      warn "warning: passing arguments to Enumerable#to_set is deprecated"
    end
    (args[0] || Set).new(self, &block)
  end
end
