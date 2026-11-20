# frozen_string_literal: true

require "cora/gem_patches"

module Cora
  module GemPatches
    module SpecificationActivation
      def activate
        activated = super
        Cora::GemPatches.apply(self) if activated
        activated
      end
    end

    module LoadPathActivation
      def add_to_load_path(*paths)
        result = super
        # Bundler marks all specs loaded before adding their paths, bypassing
        # Specification#activate. Patches can require their gems at this point.
        Gem.loaded_specs.each_value { |spec| Cora::GemPatches.apply(spec) }
        result
      end
    end
  end
end

# Gem paths and metadata are visible after activation, while activation still
# precedes requiring the gem's entrypoint.
Gem::Specification.prepend(Cora::GemPatches::SpecificationActivation)
Gem.singleton_class.prepend(Cora::GemPatches::LoadPathActivation)
