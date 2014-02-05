module Nested
  module WithModelBlock
    def model(&block)
      @model_block = block
      self
    end
  end
end