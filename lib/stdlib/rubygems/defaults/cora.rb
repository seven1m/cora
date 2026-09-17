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
  end
end

# Gem paths and metadata are visible after activation, while activation still
# precedes requiring the gem's entrypoint.
Gem::Specification.prepend(Cora::GemPatches::SpecificationActivation)
