module Nested
  module WithMany
    def many(name, init_block=nil, &block)
      many_if(PROC_TRUE, name, init_block, &block)
    end

    def many_if(resource_if_block, name, init_block=nil, &block)
      child_resource(name, Many, resource_if_block, init_block, &block)
    end
  end
end