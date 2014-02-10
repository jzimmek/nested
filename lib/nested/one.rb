module Nested
  class One < Resource
    include WithMany

    MODEL_BLOCK = Proc.new do
      if @__resource.parent
        parent_model = instance_variable_get("@#{@__resource.parent.instance_variable_name}")

        if parent_model.respond_to?(:where)
          parent_model
            .where(id: params[:"#{@__resource.parent.name.to_s.singularize.to_sym}_id"])
            .first
        elsif parent_model.respond_to?(:detect)
          parent_model.detect do |r|
            (r.is_a?(Hash) ? HashWithIndifferentAccess.new(r)[:id] : r.id).to_s == params[:"#{@__resource.parent.name.to_s.singularize.to_sym}_id"]
          end
        else
          nil
        end
      else
        nil
      end
    end


    def initialize_serializer_factory
      Serializer.new(parent.serializer.includes)
    end

    def default_model_block
      MODEL_BLOCK
    end

    def to_route_part
      "/:#{@name}_id"
    end

    def instance_variable_name
      parent.name.to_s.singularize.to_sym
    end
  end
end