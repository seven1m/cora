module ModuleSpecs
  class NamedClass
  end

  class Lookup
    LOOKIE = :lookie
  end

  module ClassEvalTest
    def self.get_constant_from_scope
      module_eval("Lookup")
    end

    def self.get_constant_from_scope_with_send(method)
      send(method, "Lookup")
    end
  end
end
