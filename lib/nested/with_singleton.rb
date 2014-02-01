module Nested
  module WithSingleton
    def singleton(name, init_block=nil, &block)
      singleton_if(PROC_TRUE, name, init_block, &block)
    end

    def singleton_if(resource_if_block, name, init_block=nil, &block)
      child_resource(name, Singleton, resource_if_block, init_block, &block)
    end
  end
end