module Nested
  class Many < Resource
    def one(&block)
      one_if(PROC_TRUE, &block)
    end

    def one_if(resource_if_block, &block)
      child_resource(self.name.to_s.singularize.to_sym, One, resource_if_block, nil, &block)
    end

    def default_init_block
      if parent
        Proc.new{ instance_variable_get("@#{@__resource.parent.instance_variable_name}").send(@__resource.name) }
      else
        Proc.new { nil }
      end
    end
  end
end