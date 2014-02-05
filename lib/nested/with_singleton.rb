module Nested
  module WithSingleton
    def singleton(name, model_block=nil, &block)
      singleton_if(PROC_TRUE, name, model_block, &block)
    end

    def singleton_if(resource_if_block, name, model_block=nil, &block)
      child_resource(name, Singleton, resource_if_block, model_block, &block)
    end
  end
end