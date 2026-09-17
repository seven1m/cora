# frozen_string_literal: true

module Cora
  module GemPatches
    Patch = Struct.new(:gem_name, :requirement, :feature, :loader)

    @patches = []
    @applied = {}

    class << self
      def register(gem_name, requirement, feature = nil, &loader)
        raise ArgumentError, "provide a feature or block" unless feature || loader

        @patches << Patch.new(
          gem_name,
          Gem::Requirement.new(requirement),
          feature,
          loader
        )
      end

      def apply(spec)
        return unless RUBY_ENGINE == "cora"

        @patches.each_with_index do |patch, index|
          next unless patch.gem_name == spec.name
          next unless patch.requirement.satisfied_by?(spec.version)

          key = [spec.full_name, index]
          next if @applied[key]

          if patch.loader
            patch.loader.call(spec)
          else
            require patch.feature
          end

          @applied[key] = true
          warn "cora: applied compatibility patch for #{spec.full_name}"
        end
      end
    end

    register "concurrent-ruby", "~> 1.3.0", "cora/gem_patches/concurrent_ruby"
  end
end
