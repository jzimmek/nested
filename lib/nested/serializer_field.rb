module Nested
  class SerializerField
    attr_accessor :name, :condition
    def initialize(name, condition)
      @name = name
      @condition = condition
    end
  end
end