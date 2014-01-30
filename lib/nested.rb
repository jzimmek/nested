require "json"

module Nested

  class OneWithNameInManyError < StandardError
  end

  class ManyInManyError < StandardError
  end

  class SingletonAndCollectionError < StandardError
  end

  class NameMissingError < StandardError
  end

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

  class Resource
    attr_reader :name, :parent, :actions, :resources, :serializer

    def initialize(sinatra, name, singleton, collection, parent, init_block)
      raise SingletonAndCollectionError.new if singleton && collection
      raise NameMissingError.new if (singleton || collection) && !name

      @sinatra = sinatra
      @name = name
      @singleton = singleton
      @collection = collection
      @parent = parent
      @resources = []
      @actions = []
      @init_block = init_block
      @run_blocks = []

      @serializer = Serializer.new(member? ? parent.serializer.includes : [])
    end

    def singleton?
      @singleton == true
    end

    def member?
      !singleton? && !collection?
    end

    def collection?
      @collection == true
    end

    def run(&block)
      @run_blocks << block
      self
    end

    def type
      if singleton?
        :singleton
      elsif member?
        :member
      elsif collection?
        :collection
      else
        raise "undefined"
      end
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


        if singleton? || collection?
          r << "/#{@name}"
        else
          r << "/:#{@name}_id"
        end

        r << "/#{action}" if action
      end
    end

    def get(action=nil, &block)
      create_sinatra_route :get, action, &(block||proc {})
    end

    def post(action=nil, &block)
      create_sinatra_route :post, action, &block
    end

    def put(action=nil, &block)
      create_sinatra_route :put, action, &block
    end

    def delete(action=nil, &block)
      create_sinatra_route :delete, action, &block
    end

    def singleton(name, init_block=nil, &block)
      child_resource(name, true, false, init_block, &(block||Proc.new{ }))
    end

    def many(name, init_block=nil, &block)
      raise ManyInManyError.new "do not nest many in many" if collection?
      child_resource(name, false, true, init_block, &(block||Proc.new{ }))
    end

    def default_init_block_singleton
      if parent
        Proc.new{ instance_variable_get("@#{@__resource.parent.instance_variable_name}").send(@__resource.name) }
      else
        Proc.new { nil }
      end
    end

    def default_init_block_many
      if parent
        Proc.new{ instance_variable_get("@#{@__resource.parent.instance_variable_name}").send(@__resource.name) }
      else
        Proc.new { nil }
      end
    end

    def default_init_block_one
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

    def one(&block)
      raise "calling one() is only allowed within many() resource" unless collection?
      child_resource(self.name.to_s.singularize.to_sym, false, false, nil, &(block||Proc.new{ }))
    end

    def child_resource(name, singleton, collection, init_block, &block)
       Resource.new(@sinatra, name, singleton, collection, self, init_block)
        .tap{|r| r.instance_eval(&block)}
        .tap{|r| @resources << r}
    end

    def instance_variable_name
      member? ? parent.name.to_s.singularize.to_sym : @name
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

      init_block = if @init_block
        @init_block
      else
        if singleton?
          default_init_block_singleton
        elsif collection?
          default_init_block_many
        else
          default_init_block_one
        end
      end

      sinatra.instance_variable_set("@#{self.instance_variable_name}", sinatra.instance_exec(&init_block))

      @run_blocks.each{|e| sinatra.instance_exec(&e)}
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
      data = if response && (collection? || response.is_a?(Array)) && method != :post
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

    def create_sinatra_route(method, action, &block)
      @actions << {method: method, action: action, block: block}

      resource = self

      route = resource.route(action)
      puts "sinatra router [#{method}] #{@sinatra.nested_config[:prefix]}#{route}"

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

          resource.send(:"sinatra_exec_#{method}_block", self, &block)

          resource.sinatra_response(self, method)
        rescue Exception => e
          context_arr = []
          context_arr << "route: #{route}"
          context_arr << "method: #{method}"
          context_arr << "action: #{action}"

          context_arr << "resource: #{resource.name} (#{resource.type})"
          resource_object = instance_variable_get("@#{resource.instance_variable_name}")
          context_arr << "@#{resource.instance_variable_name}: #{resource_object.inspect}"

          parent = resource.try(:parent)

          if parent
            context_arr << "parent: #{parent.try(:name)} (#{parent.try(:type)})"
            parent_object = instance_variable_get("@#{parent.try(:instance_variable_name)}")
            context_arr << "@#{parent.try(:instance_variable_name)}: #{parent_object.inspect}"
          end

          puts context_arr.join("\n")
          raise e
        end
      end
    end
  end

  module Angular
    def self.extended(base)
      base.send(:extend, Nested::Angular::Sinatra)
    end

    module Sinatra
      # def create_resource(name, singleton, collection, &block)
      def create_resource(*args, &block)
        angularize(super)
      end

      def nested_angular_config(config=nil)
        if config
          @nested_angular_config = config
        else
          @nested_angular_config ||= {}
        end
      end

    end

    def angular_add_functions(js, resource)
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
        route = "#{self.nested_config[:prefix]}" + resource.route_replace(resource.route(action), route_args)
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

      resource.resources.each {|r| angular_add_functions(js, r) }
    end

    def angularize(resource)
      js = []

      module_name = "nested_#{resource.name}".camelcase(:lower)

      js << "angular.module('#{module_name}#{nested_angular_config[:service_suffix]}', [])"
      js << ".factory('#{resource.name.to_s.camelcase.capitalize}#{nested_angular_config[:service_suffix]}', function($http, $q){"

      js << "  var impl = {}"
      angular_add_functions(js, resource)
      js << "  return impl"

      js << "})"

      response_transform = nested_angular_config[:response_transform] || ->(code){ code }

      get "/#{resource.name}.js" do
        content_type :js
        instance_exec(js.join("\n"), &response_transform)
      end
    end
  end

  module JsUtil
    def self.generate_function_name(resource, method, action)
      arr = []

      arr << "update" if method == :put
      arr << "create" if method == :post
      arr << "destroy" if method == :delete

      parents = resource.parents
      parents.each_with_index do |p, idx|
        if p.collection? && method != :post && ((parents[idx + 1] && parents[idx + 1].singleton?) || parents.last == p)
          arr << p.name.to_s.send(:pluralize)
        else
          arr << p.name.to_s.send(:singularize)
        end
      end

      if resource.member?
        if resource.parent
          arr = arr.slice(0...-1)
          arr << resource.parent.name.to_s.send(:singularize)
        else
          arr << resource.name.to_s.send(:singularize)
        end
      elsif resource.singleton?
        arr << resource.name.to_s.send(:singularize)
      elsif resource.collection?
        if method == :post
          arr << resource.name.to_s.send(:singularize)
        else
          arr << resource.name.to_s.send(:pluralize)
        end
      end

      arr << action if action

      arr.map(&:to_s).join("_").camelcase(:lower)
    end

    def self.function_arguments(resource)
      resource
        .self_and_parents.select{|r| r.member?}
        .map{|r| r.name || r.parent.name}
        .map(&:to_s)
        .map(&:singularize)
        .reverse
    end
  end

  module Sinatra
    def nested_config(config=nil)
      if config
        @nested_config = config
      else
        @nested_config ||= {}
      end
    end
    def singleton(name, init_block=nil, &block)
      create_resource(name, true, false, init_block, &block)
    end
    def many(name, init_block=nil, &block)
      create_resource(name, false, true, init_block, &block)
    end
    def one(name, init_block=nil, &block)
      create_resource(name, false, false, init_block, &block)
    end
    def create_resource(name, singleton, collection, init_block, &block)
      ::Nested::Resource.new(self, name, singleton, collection, nil, init_block).tap{|r| r.instance_eval(&block) }
    end
  end

end
