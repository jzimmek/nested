require "json"
require "sinatra/base"

module Nested

  PROC_TRUE = Proc.new{ true }

  class Redirect
    attr_reader :url
    def initialize(url)
      @url = url
    end
  end

  class SerializerField
    attr_accessor :name, :condition
    def initialize(name, condition)
      @name = name
      @condition = condition
    end
  end

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
        excludes = this.excludes.select{|e| instance_exec(&e.condition)}

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
      end
    end
  end

  module WithMany
    def many(name, init_block=nil, &block)
      many_if(PROC_TRUE, name, init_block, &block)
    end

    def many_if(resource_if_block, name, init_block=nil, &block)
      child_resource(name, Many, resource_if_block, init_block, &block)
    end
  end

  module WithSingleton
    def singleton(name, init_block=nil, &block)
      singleton_if(PROC_TRUE, name, init_block, &block)
    end

    def singleton_if(resource_if_block, name, init_block=nil, &block)
      child_resource(name, Singleton, resource_if_block, init_block, &block)
    end
  end

  class Resource
    attr_reader :name, :parent, :actions, :resources, :serializer, :init_block, :sinatra

    include WithSingleton

    def initialize(sinatra, name, parent, resource_if_block, init_block)
      raise "resource must be given a name" unless name

      @sinatra = sinatra
      @name = name
      @parent = parent
      @resources = []
      @actions = []

      raise "resource_if_block is nil, pass Nested::PROC_TRUE instead" unless resource_if_block
      @resource_if_block = resource_if_block

      unless @init_block = init_block
        if is_a?(One)
          @init_block = default_init_block
        else
          @init_block = resource_if_block != PROC_TRUE ? parent.try(:init_block) : default_init_block
        end
      end

      raise "no init_block passed and could not lookup any parent or default init_block" unless @init_block

      @before_blocks = []
      @after_blocks = []

      @serializer = initialize_serializer_factory
    end

    def initialize_serializer_factory
      Serializer.new([])
    end

    def child_resource(name, clazz, resource_if_block, init_block, &block)
       clazz.new(@sinatra, name, self, resource_if_block, init_block)
        .tap{|r| r.instance_eval(&(block||Proc.new{ }))}
        .tap{|r| @resources << r}
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
      serializer
    end

    def serialize_include_if(condition, *args)
      args.each {|arg| @serializer + SerializerField.new(arg, condition) }
    end

    def serialize_exclude_if(condition, *args)
      args.each {|arg| @serializer - SerializerField.new(arg, condition) }
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
        end

        define_method :"#{method}_if" do |method_if_block, action=nil, &block|
          create_sinatra_route method, action, method_if_block, &(block||proc {})
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
      sinatra.instance_variable_set("@__resource", self)

      raise "resource_if is false for resource: #{self.name} " unless sinatra.instance_exec(&@resource_if_block)

      @before_blocks.each{|e| sinatra.instance_exec(&e)}

      sinatra.instance_variable_set("@#{self.instance_variable_name}", sinatra.instance_exec(&@init_block))

      @after_blocks.each{|e| sinatra.instance_exec(&e)}
    end

    def sinatra_exec_get_block(sinatra, &block)
      sinatra_init_data(:get, sinatra, &block)
      sinatra.instance_exec(*sinatra.instance_variable_get("@__data"), &block)
    end

    def sinatra_exec_delete_block(sinatra, &block)
      sinatra_init_data(:delete, sinatra, &block)
      sinatra.instance_exec(*sinatra.instance_variable_get("@__data"), &block)
    end

    def sinatra_init_data(method, sinatra, &block)
      raw_data = if [:put, :post].include?(method)
        sinatra.request.body.rewind
        HashWithIndifferentAccess.new(JSON.parse(sinatra.request.body.read))
      elsif [:get, :delete].include?(method)
        sinatra.params
      else
        {}
      end

      sinatra.instance_variable_set("@__raw_data", raw_data)
      sinatra.instance_variable_set("@__data", raw_data.values_at(*block.parameters.map(&:last)))
    end

    def sinatra_exec_put_block(sinatra, &block)
      sinatra_init_data(:put, sinatra, &block)
      sinatra.instance_exec(*sinatra.instance_variable_get("@__data"), &block)
    end

    def sinatra_exec_post_block(sinatra, &block)
      sinatra_init_data(:post, sinatra, &block)
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

          context_arr << "resource: #{resource.name} (#{resource.class.name})"
          resource_object = instance_variable_get("@#{resource.instance_variable_name}")
          context_arr << "@#{resource.instance_variable_name}: #{resource_object.inspect}"

          parent = resource.try(:parent)

          if parent
            context_arr << "parent: #{parent.name} (#{parent.class.name})"
            parent_object = instance_variable_get("@#{parent.instance_variable_name}")
            context_arr << "@#{parent.instance_variable_name}: #{parent_object.inspect}"
          end

          puts context_arr.join("\n")
          raise e
        end
      end
    end
  end

  class Singleton < Resource
    include WithMany

    def default_init_block
      if parent
        Proc.new{ instance_variable_get("@#{@__resource.parent.instance_variable_name}").send(@__resource.name) }
      else
        Proc.new { nil }
      end
    end
  end

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

  class One < Resource
    include WithMany

    def initialize_serializer_factory
      Serializer.new(parent.serializer.includes)
    end

    def default_init_block
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

  module Angular
    def self.extended(clazz)
      (class << clazz; self; end).instance_eval do
        attr_accessor :angular_config
      end
      clazz.angular_config = {}

      def clazz.angular(opts={})
        @angular_config.merge!(opts)
      end

      def child_resource(*args, &block)
        Helper::angularize(self, super)
      end
    end

    module Helper
      def self.angular_add_functions(app, js, resource)
        resource.actions.each do |e|
          method, action, block = e.values_at :method, :action, :block
          block_args = block.parameters.map(&:last)

          fun_name = Nested::JsUtil::generate_function_name(resource, method, action)

          args = Nested::JsUtil::function_arguments(resource)

          route_args = args.inject({}) do |memo, e|
            idx = args.index(e)
            memo[:"#{e}_id"] = "'+(typeof(values[#{idx}]) == 'number' ? values[#{idx}].toString() : (values[#{idx}].id || values[#{idx}]))+'"
            memo
          end
          route = "#{app.config[:prefix]}" + resource.route_replace(resource.route(action), route_args)
          when_args = args.map{|a| "$q.when(#{a})"}

          js << "  impl.#{fun_name}Url = function(#{args.join(',')}){"
          js << "    var deferred = $q.defer()"
          js << "    $q.all([#{when_args.join(',')}]).then(function(values){"
          js << "      deferred.resolve('#{route}')"
          js << "    })"
          js << "    return deferred.promise"
          js << "  }"

          if [:get, :delete].include?(method)
            args << "data" if !block_args.empty?

            js << "  impl.#{fun_name} = function(#{args.join(',')}){"
            js << "    var deferred = $q.defer()"
            js << "    $q.all([#{when_args.join(',')}]).then(function(values){"
            js << "      $http({"
            js << "         method: '#{method}', "
            js << ("         url: '#{route}'" + (block_args.empty? ? "" : ","))
            js << "         params: data" unless block_args.empty?
            js << "      })"
            js << "        .success(function(responseData){"
            js << "           deferred[responseData.ok ? 'resolve' : 'reject'](responseData.data)"
            js << "        })"
            js << "        .error(function(){ deferred.reject() })"
            js << "    });"
            js << "    return deferred.promise"
            js << "  }"
          elsif method == :post
            js << "  impl.#{fun_name} = function(#{(args+['data']).join(',')}){"
            js << "    var deferred = $q.defer()"
            js << "    $q.all([#{when_args.join(',')}]).then(function(values){"
            js << "      $http({method: '#{method}', url: '#{route}', data: data})"
            js << "        .success(function(responseData){"
            js << "           deferred[responseData.ok ? 'resolve' : 'reject'](responseData.data)"
            js << "        })"
            js << "        .error(function(){ deferred.reject() })"
            js << "    });"
            js << "    return deferred.promise"
            js << "  }"
          elsif method == :put
            args << "data" if args.empty? || !block_args.empty?

            js << "  impl.#{fun_name} = function(#{args.join(',')}){"
            js << "    var deferred = $q.defer()"
            js << "    $q.all([#{when_args.join(',')}]).then(function(values){"
            js << "      $http({method: '#{method}', url: '#{route}', data: #{args.last}})"
            js << "        .success(function(responseData){"
            js << "           deferred[responseData.ok ? 'resolve' : 'reject'](responseData.data)"
            js << "        })"
            js << "        .error(function(){ deferred.reject() })"
            js << "    });"
            js << "    return deferred.promise"
            js << "  }"
          end
        end

        resource.resources.each {|r| angular_add_functions(app, js, r) }
      end

      def self.angularize(app, resource)
        js = []

        module_name = "nested_#{resource.name}".camelcase(:lower)

        js << "angular.module('#{module_name}#{app.angular_config[:service_suffix]}', [])"
        js << ".factory('#{resource.name.to_s.camelcase.capitalize}#{app.angular_config[:service_suffix]}', function($http, $q){"

        js << "  var impl = {}"
        angular_add_functions(app, js, resource)
        js << "  return impl"

        js << "})"

        response_transform = app.angular_config[:response_transform] || ->(code){ code }

        app.sinatra.get "/#{resource.name}.js" do
          content_type :js
          instance_exec(js.join("\n"), &response_transform)
        end
      end
    end
  end

  module JsUtil
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

  class App
    def self.inherited(clazz)
      (class << clazz; self; end).instance_eval do
        attr_accessor :sinatra
      end
      clazz.sinatra = Class.new(Sinatra::Base)
      clazz.instance_variable_set("@config", {})
    end

    def self.child_resource(name, clazz, resource_if_block, init_block, &block)
       clazz.new(sinatra, name, nil, resource_if_block, init_block)
            .tap{|r| r.instance_eval(&(block||Proc.new{ }))}
    end

    def self.before(&block)
      sinatra.before(&block)
    end

    def self.after(&block)
      sinatra.after(&block)
    end

    def self.config(opts={})
      @config.tap{|c| c.merge!(opts)}
    end

    extend WithSingleton
    extend WithMany
  end
end
