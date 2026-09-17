# frozen_string_literal: true

require "concurrent/utility/engine"

# concurrent-ruby otherwise selects its fully synchronized fallback for Cora.
# That backend recursively locks when a map default proc writes through the map,
# as TZInfo's ConcurrentStringDeduper does. Cora's serialized Ruby execution can
# use the same backend as CRuby without changing RUBY_ENGINE globally.
module Concurrent
  class << self
    alias_method :cora_original_on_cruby?, :on_cruby?

    def on_cruby?
      RUBY_ENGINE == "cora" || cora_original_on_cruby?
    end
  end
end
