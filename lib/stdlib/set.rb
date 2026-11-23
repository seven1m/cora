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

  def initialize_dup(original)
    super
    @hash = original.instance_variable_get(:@hash).dup
  end

  def initialize_clone(original, freeze: nil)
    super
    @hash = original.instance_variable_get(:@hash).dup
    @hash.freeze if freeze || (freeze.nil? && original.frozen?)
  end

  def freeze
    @hash.freeze
    super
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
  alias === include?

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
    @hash.delete(obj)
    self
  end

  def delete?(obj)
    @hash.delete(obj) ? self : nil
  end

  def delete_if
    return enum_for(:delete_if) unless block_given?

    select { |obj| yield obj }.each { |obj| @hash.delete(obj) }
    self
  end

  def keep_if
    return enum_for(:keep_if) unless block_given?

    reject { |obj| yield obj }.each { |obj| @hash.delete(obj) }
    self
  end

  def reject!
    return enum_for(:reject!) unless block_given?

    original_size = size
    delete_if { |obj| yield obj }
    self if size != original_size
  end

  def select!
    return enum_for(:select!) unless block_given?

    original_size = size
    keep_if { |object| yield object }
    self if size != original_size
  end
  alias filter! select!

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

  def join(separator = nil)
    to_a.join(separator)
  end

  def classify
    return enum_for(:classify) { size } unless block_given?

    groups = {}
    each do |object|
      key = yield object
      (groups[key] ||= empty_set).add(object)
    end
    groups
  end

  def divide(&block)
    return enum_for(:divide) { size } unless block
    return Set.new(classify(&block).values) unless block.arity == 2

    # A binary relation partitions the set into strongly connected components.
    # Compare graph nodes by identity, including for identity-comparing Sets.
    nodes = to_a
    edges = {}.compare_by_identity
    nodes.each do |node|
      edges[node] = nodes.select do |other|
        !node.equal?(other) && block.call(node, other)
      end
    end
    indices = {}.compare_by_identity
    lowlinks = {}.compare_by_identity
    active = {}.compare_by_identity
    stack = []
    groups = []
    index = 0
    visit = nil
    visit = lambda do |node|
      indices[node] = index
      lowlinks[node] = index
      index += 1
      stack << node
      active[node] = true
      edges[node].each do |other|
        unless indices.key?(other)
          visit.call(other)
          lowlinks[node] = [lowlinks[node], lowlinks[other]].min
        else
          lowlinks[node] = [lowlinks[node], indices[other]].min if active[other]
        end
      end
      if lowlinks[node] == indices[node]
        component = empty_set
        loop do
          member = stack.pop
          active.delete(member)
          component.add(member)
          break if member.equal?(node)
        end
        groups << component
      end
    end
    nodes.each { |node| visit.call(node) unless indices.key?(node) }
    Set.new(groups)
  end

  def flatten
    result = empty_set
    flatten_into(result, {}.compare_by_identity)
    result
  end

  def flatten!
    return nil unless any? { |object| object.is_a?(Set) }

    replace(flatten)
  end

  def pretty_print_cycle(printer)
    printer.text("#{self.class}[...]")
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

  def <=>(other)
    return nil unless other.is_a?(Set)
    return 0 if self == other
    return -1 if proper_subset?(other)
    return 1 if proper_superset?(other)

    nil
  end

  def superset?(other)
    raise ArgumentError, "value must be a set" unless other.is_a?(Set)

    size >= other.size && other.all? { |object| include?(object) }
  end
  alias >= superset?

  def proper_superset?(other)
    raise ArgumentError, "value must be a set" unless other.is_a?(Set)

    size > other.size && other.all? { |object| include?(object) }
  end
  alias > proper_superset?

  def subset?(other)
    raise ArgumentError, "value must be a set" unless other.is_a?(Set)

    size <= other.size && all? { |object| other.include?(object) }
  end
  alias <= subset?

  def proper_subset?(other)
    raise ArgumentError, "value must be a set" unless other.is_a?(Set)

    size < other.size && all? { |object| other.include?(object) }
  end
  alias < proper_subset?

  def intersect?(other)
    raise ArgumentError, "value must be a set" unless other.is_a?(Set)

    other.any? { |object| include?(object) }
  end

  def disjoint?(other)
    !intersect?(other)
  end

  def replace(enum)
    if enum.is_a?(Set)
      @hash.replace(enum.instance_variable_get(:@hash))
    else
      replacement = {}
      replacement.compare_by_identity if @hash.compare_by_identity?
      each_from(enum) { |obj| replacement[obj] = true }
      @hash.replace(replacement)
    end
    self
  end

  def map!(&block)
    return enum_for(:map!) unless block

    replace(map(&block))
  end
  alias collect! map!

  def merge(*enums)
    enums.each do |enum|
      each_from(enum) do |obj|
        add(obj)
      end
    end
    self
  end

  def subtract(enum)
    each_from(enum) do |obj|
      delete(obj)
    end
    self
  end

  def |(enum)
    dup.merge(enum)
  end
  alias + |
  alias union |

  def -(enum)
    dup.subtract(enum)
  end
  alias difference -

  def &(enum)
    other = enum.is_a?(Set) ? enum : empty_set.merge(enum)
    result = empty_set
    each { |object| result.add(object) if other.include?(object) }
    result
  end
  alias intersection &

  def ^(enum)
    other = empty_set.merge(enum)
    result = dup
    other.each do |object|
      include?(object) ? result.delete(object) : result.add(object)
    end
    result
  end

  private

  def empty_set
    result = self.class.new
    result.compare_by_identity if compare_by_identity?
    result
  end

  def flatten_into(result, visiting)
    raise ArgumentError, "tried to flatten recursive Set" if visiting.key?(self)

    visiting[self] = true
    begin
      each do |object|
        if object.is_a?(Set)
          object.send(:flatten_into, result, visiting)
        else
          result.add(object)
        end
      end
    ensure
      visiting.delete(self)
    end
    result
  end

  def each_from(enum, &block)
    if enum.respond_to?(:each_entry)
      enum.each_entry(&block)
    elsif enum.respond_to?(:each)
      enum.each(&block)
    else
      raise ArgumentError, "value must be enumerable"
    end
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
