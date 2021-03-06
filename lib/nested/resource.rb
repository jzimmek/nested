module Nested
  class Resource
    attr_reader :name, :parent, :actions, :resources, :serializer, :model_block, :sinatra, :before_blocks, :after_blocks

    include WithSingleton

    def initialize(app, sinatra, name, parent, resource_if_block, model_block)
      raise "resource must be given a name" unless name

      @app = app
      @sinatra = sinatra
      @name = name
      @parent = parent
      @resources = []
      @actions = []

      raise "resource_if_block is nil, pass Nested::PROC_TRUE instead" unless resource_if_block
      @resource_if_block = resource_if_block

      unless @model_block = model_block
        if is_a?(One)
          @model_block = default_model_block
        else
          @model_block = resource_if_block != PROC_TRUE ? parent.try(:model_block) : default_model_block
        end
      end

      raise "no model_block passed and could not lookup any parent or default model_block" unless @model_block

      @before_blocks = []
      @after_blocks = []

      @serializer = initialize_serializer_factory
    end

    def behave(name)
      instance_exec(&@app.behaviors[name])
    end

    def initialize_serializer_factory
      Serializer.new([])
    end

    def child_resource(name, clazz, resource_if_block, model_block, &block)
       clazz.new(@app, @sinatra, name, self, resource_if_block, model_block)
        .tap{|r| r.instance_eval(&(block||Proc.new{ }))}
        .tap{|r| @resources << r}
    end

    def default_model_block
      raise "implement me"
    end

    def to_route_part
      "/#{@name}"
    end

    def before(&block)
      @before_blocks << block
      self
    end

    def after(&block)
      @after_blocks << block
      self
    end

    def serialize(*args)
      args.each {|arg| serializer + arg }
      self
    end

    def serialize_include_if(condition, *args)
      args.each {|arg| @serializer + SerializerField.new(arg, condition.is_a?(Symbol) ? @app.conditions[condition] : condition) }
      self
    end

    def serialize_exclude_if(condition, *args)
      args.each {|arg| @serializer - SerializerField.new(arg, condition.is_a?(Symbol) ? @app.conditions[condition] : condition) }
      self
    end

    def route_replace(route, args)
      args.each do |k, v|
        route = route.gsub(":#{k}", "#{v}")
      end
      route
    end

    def route(action=nil)
      "".tap do |r|
        r << @parent.route if @parent
        r << to_route_part
        r << "/#{action}" if action
      end
    end

    [:get, :post, :put, :delete].each do |method|
      instance_eval do
        define_method method do |action=nil, &block|
          send(:"#{method}_if", PROC_TRUE, action, &block)
          self
        end

        define_method :"#{method}_if" do |method_if_block, action=nil, &block|
          create_sinatra_route method, action, method_if_block.is_a?(Symbol) ? @app.conditions[method_if_block] : method_if_block, &(block||proc {})
          self
        end
      end
    end

    def instance_variable_name
      @name
    end

    def parents
      (@parent ? @parent.parents + [@parent] : [])
    end

    def self_and_parents
      (self.parents + [self]).reverse
    end

    # --------------------------

    def sinatra_set_instance_variable(sinatra, name, value)
      raise "variable @#{name} already defined" if sinatra.instance_variable_defined?(:"@#{name}")
      sinatra.instance_variable_set(:"@#{name}", value)
    end

    def sinatra_init(sinatra)
      sinatra_init_set_resource(sinatra)

      raise "resource_if is false for resource: #{self.name} " unless sinatra.instance_exec(&@resource_if_block)

      sinatra_init_before(sinatra)
      sinatra_init_set_model(sinatra)
      sinatra_init_after(sinatra)
    end

    def sinatra_init_set_resource(sinatra)
      sinatra.instance_variable_set("@__resource", self)
    end

    def sinatra_init_set_model(sinatra)
      sinatra.instance_variable_set("@#{self.instance_variable_name}", sinatra.instance_exec(*(@model_block.parameters.empty? ? [] : [sinatra.instance_exec(&default_model_block)]), &@model_block))
    end

    def sinatra_init_before(sinatra)
      @before_blocks.each{|e| sinatra.instance_exec(&e)}
    end

    def sinatra_init_after(sinatra)
      @after_blocks.each{|e| sinatra.instance_exec(&e)}
    end

    def sinatra_exec_get_block(sinatra, &block)
      # sinatra_init_data(:get, sinatra, &block)
      sinatra.instance_exec(*sinatra.instance_variable_get("@__data"), &block)
    end

    def sinatra_exec_delete_block(sinatra, &block)
      # sinatra_init_data(:delete, sinatra, &block)
      sinatra.instance_exec(*sinatra.instance_variable_get("@__data"), &block)
    end

    # def sinatra_init_data(method, sinatra, &block)
    #   raw_data = if [:put, :post].include?(method)
    #     sinatra.request.body.rewind
    #     body = sinatra.request.body.read
    #     HashWithIndifferentAccess.new(JSON.parse(body))
    #   elsif [:get, :delete].include?(method)
    #     sinatra.params
    #   else
    #     {}
    #   end

    #   sinatra.instance_variable_set("@__raw_data", raw_data)
    #   sinatra.instance_variable_set("@__data", raw_data.values_at(*block.parameters.map(&:last)))
    # end

    def sinatra_exec_put_block(sinatra, &block)
      # sinatra_init_data(:put, sinatra, &block)
      sinatra.instance_exec(*sinatra.instance_variable_get("@__data"), &block)
    end

    def sinatra_exec_post_block(sinatra, &block)
      # sinatra_init_data(:post, sinatra, &block)
      res = sinatra.instance_exec(*sinatra.instance_variable_get("@__data"), &block)
      sinatra.instance_variable_set("@#{self.instance_variable_name}", res)
      # TODO: do we need to check for existing variables here?
      # sinatra_set_instance_variable(sinatra, self.instance_variable_name, res)
    end

    def sinatra_response_type(response)
      (response.is_a?(ActiveModel::Errors) || (response.respond_to?(:errors) && !response.errors.empty?)) ? :error : (response.is_a?(Nested::Redirect) ? :redirect : :data)
    end

    def sinatra_response(sinatra, method)
      response = if sinatra.errors.empty?
        sinatra.instance_variable_get("@#{self.instance_variable_name}")
      else
        sinatra.errors
      end

      response = self.send(:"sinatra_response_create_#{sinatra_response_type(response)}", sinatra, response, method)

      case response
        when Nested::Redirect then
          sinatra.redirect(response.url)
        when String then
          response
        else
          response.to_json
      end
    end

    def sinatra_response_create_redirect(sinatra, response, method)
      response
    end

    def sinatra_response_create_data(sinatra, response, method)
      data = if response && (is_a?(Many) || response.is_a?(Array)) && method != :post
        response.to_a.map{|e| sinatra.instance_exec(e, &@serializer.serialize) }
      else
        sinatra.instance_exec(response, &@serializer.serialize)
      end

      {data: data, ok: true}
    end

    def sinatra_errors_to_hash(errors)
      errors.to_hash.inject({}) do |memo, e|
        memo[e[0]] = e[1][0]
        memo
      end
    end

    def sinatra_response_create_error(sinatra, response, method)
      errors = response.is_a?(ActiveModel::Errors) ? response : response.errors
      {data: sinatra_errors_to_hash(errors), ok: false}
    end

    def sinatra_init_data_extract_body(sinatra)
      JSON.parse(sinatra.request.body.read)
    end

    def sinatra_init_data(sinatra, method, &block)
      if [:put, :post].include?(method)
        sinatra.request.body.rewind
        sinatra.params.merge! HashWithIndifferentAccess.new(sinatra_init_data_extract_body(sinatra))
      end

      sinatra.instance_variable_set("@__raw_data", HashWithIndifferentAccess.new(sinatra.params))
      sinatra.instance_variable_set("@__data", HashWithIndifferentAccess.new(sinatra.params).values_at(*block.parameters.map(&:last)))
    end

    def create_sinatra_route(method, action, method_if_block, &block)
      @actions << {method: method, action: action, block: block}

      resource = self

      route = resource.route(action)

      @sinatra.send(method, route) do
        def self.error(message)
          errors.add(:base, message)
        end

        def self.errors
          @__errors ||= ActiveModel::Errors.new({})
        end

        begin
          content_type :json

          resource.sinatra_init_data(self, method, &block)

          resource.self_and_parents.reverse.each do |res|
            res.sinatra_init(self)
          end

          raise "method_if_block returns false for method: #{method}, action: #{action}, resource: #{resource.name}" unless instance_exec(&method_if_block)

          resource.send(:"sinatra_exec_#{method}_block", self, &block)

          resource.sinatra_response(self, method)
        rescue Exception => e
          context_arr = []
          context_arr << "route: #{route}"
          context_arr << "method: #{method}"
          context_arr << "action: #{action}"
          context_arr << "params: #{params.inspect}"
          context_arr << "__raw_data: #{@__raw_data.inspect}"
          context_arr << "__data: #{@__data.inspect}"


          context_arr << "resource: #{resource.name} (#{resource.class.name})"
          resource_object = instance_variable_get("@#{resource.instance_variable_name}")
          context_arr << "@#{resource.instance_variable_name}: #{resource_object.inspect}"

          resource.parents.each do |parent|
            context_arr << "parent: #{parent.name} (#{parent.class.name})"
            parent_object = instance_variable_get("@#{parent.instance_variable_name}")
            context_arr << "@#{parent.instance_variable_name}: #{parent_object.inspect}"
          end

          # parent = resource.try(:parent)

          # if parent
          #   context_arr << "parent: #{parent.name} (#{parent.class.name})"
          #   parent_object = instance_variable_get("@#{parent.instance_variable_name}")
          #   context_arr << "@#{parent.instance_variable_name}: #{parent_object.inspect}"
          # end

          puts context_arr.join("\n")
          puts e.message
        end
      end
    end
  end
end