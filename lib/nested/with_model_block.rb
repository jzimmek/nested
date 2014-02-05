module Nested
  module WithModelBlock
    def model(&block)
      raise "do not use model() when you already set a model block" if @model_block != default_model_block && @model_block != Nested::PROC_NIL
      @model_block = block
      self
    end
  end
end