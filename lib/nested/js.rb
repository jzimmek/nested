module Nested
  module Js
    def self.generate_function_name(resource, method, action)
      arr = []

      arr << "update" if method == :put
      arr << "create" if method == :post
      arr << "destroy" if method == :delete

      all = resource.self_and_parents.reverse

      all.each do |e|
        if e.is_a?(Many)
          if e == all.last
            if method == :post
              arr << e.name.to_s.singularize.to_sym
            else
              arr << e.name
            end
          else
            arr << e.name unless all[all.index(e) + 1].is_a?(One)
          end
        else
          arr << e.name
        end
      end

      arr << action if action

      arr.map(&:to_s).join("_").camelcase(:lower)
    end

    def self.function_arguments(resource)
      resource
        .self_and_parents.select{|r| r.is_a?(One)}
        .map{|r| r.name || r.parent.name}
        .map(&:to_s)
        .map(&:singularize)
        .reverse
    end
  end
end