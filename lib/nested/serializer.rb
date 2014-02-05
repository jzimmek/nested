module Nested
  class Serializer
    attr_accessor :includes, :excludes

    def initialize(includes=[])
      @includes = includes.clone
      @excludes = []
    end

    def +(field)
      field = field.is_a?(SerializerField) ? field : SerializerField.new(field, ->{ true })

      @includes << field unless @includes.detect{|e| e.name == field.name}
      @excludes = @excludes.reject{|e| e.name == field.name}
      self
    end

    def -(field)
      field = field.is_a?(SerializerField) ? field : SerializerField.new(field, ->{ true })

      @excludes << field unless @excludes.detect{|e| e.name == field.name}
      self
    end

    def serialize
      this = self
      ->(obj) do
        obj = ::HashWithIndifferentAccess.new(obj) if obj.is_a?(Hash)

        excludes = this.excludes.select{|e| instance_exec(&e.condition)}

        if obj
          this.includes.reject{|e| excludes.detect{|e2| e2.name == e.name}}.inject({}) do |memo, field|
            if instance_exec(&field.condition)
              case field.name
                when Symbol
                  memo[field.name] = obj.is_a?(Hash) ? obj[field.name] : obj.send(field.name)
                when Hash
                  field_name, proc = field.name.to_a.first
                  memo[field_name] = instance_exec(obj, &proc)
              end
            end
            memo
          end
        else
          nil
        end
      end
    end
  end
end