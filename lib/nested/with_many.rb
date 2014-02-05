module Nested
  module WithMany
    def many(name, model_block=nil, &block)
      many_if(PROC_TRUE, name, model_block, &block)
    end

    def many_if(resource_if_block, name, model_block=nil, &block)
      child_resource(name, Many, resource_if_block, model_block, &block)
    end
  end
end