module Nested
  class One < Resource
    include WithMany

    def initialize_serializer_factory
      Serializer.new(parent.serializer.includes)
    end

    def default_model_block
      if parent
        Proc.new do
          instance_variable_get("@#{@__resource.parent.instance_variable_name}")
            .where(id: params[:"#{@__resource.parent.name.to_s.singularize.to_sym}_id"])
            .first
        end
      else
        Proc.new { nil }
      end
    end

    def to_route_part
      "/:#{@name}_id"
    end

    def instance_variable_name
      parent.name.to_s.singularize.to_sym
    end
  end
end