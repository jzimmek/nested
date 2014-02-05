module Nested
  class Singleton < Resource
    include WithMany
    include WithModelBlock

    MODEL_BLOCK = Proc.new do
      if @__resource.parent
        instance_variable_get("@#{@__resource.parent.instance_variable_name}").send(@__resource.name)
      else
        nil
      end
    end

    def default_model_block
      MODEL_BLOCK
    end
  end
end