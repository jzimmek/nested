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

  class Resource
    FETCH = -> do
      raise "implement fetch for resource #{@__resource.name}"  unless @__resource.parent
      raise "implement fetch for singleton #{@__resource.name}" if @__resource.singleton?

      parent_resource = @__resource.parent
      parent_obj = instance_variable_get("@#{parent_resource.instance_variable_name}")

      if @__resource.name
        scope = parent_obj.send(@__resource.name.to_s.pluralize.to_sym)
        @__resource.collection? ? scope : scope.where(id: params["#{@__resource.name.to_s.singularize}_id"]).first
      else
        parent_obj.where(id: params["#{parent_resource.name.to_s.singularize}_id"]).first
      end
    end

    attr_reader :name, :parent, :actions, :resources

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

      init &-> do
        fetched = instance_exec(&(init_block||FETCH))

        # puts "set @#{@__resource.instance_variable_name} to #{fetched.inspect} for #{self}"
        # self.instance_variable_set("@#{@__resource.instance_variable_name}", fetched)
        @__resource.sinatra_set_instance_variable(self, @__resource.instance_variable_name, fetched)
      end

      if member?
        __serialize_args = @parent.instance_variable_get("@__serialize_args")
        __serialize_block = @parent.instance_variable_get("@__serialize_block")

        serialize *__serialize_args, &__serialize_block
      else
        serialize &->(obj) { obj }
      end
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

    def serialize(*args, &block)
      raise "pass either *args or &block" if args.empty? && !block && !member?

      @__serialize_args = args
      @__serialize_block = block

      @__serialize = ->(obj) do
        obj = self.instance_exec(obj, &block) if block
        obj = obj.attributes if obj.is_a?(ActiveRecord::Base)
        obj = obj.symbolize_keys.slice(*args) unless args.empty?
        obj
      end
    end

    def init(&block)
      @__init = block
    end

    def route(args={}, action=nil)
      "".tap do |r|
        r << @parent.route(args) if @parent

        if singleton?
          r << "/" + @name.to_s.singularize
        elsif collection?
          r << "/" + @name.to_s.pluralize
        else
          if @name
            r << "/" + @name.to_s.pluralize
          end
          r << "/"
          key = ((@name || @parent.name).to_s.singularize + "_id").to_sym

          if args.key?(key)
            r << args[key].to_s
          else
            r << ":#{key}"
          end
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
      child_resource(name, true, false, init_block, &block)
    end

    def many(name, init_block=nil, &block)
      raise ManyInManyError.new "do not nest many in many" if collection?
      child_resource(name, false, true, init_block, &block)
    end

    def one(name=nil, init_block=nil, &block)
      raise OneWithNameInManyError.new("call one (#{name}) without name argument when nested in a many (#{@name})") if name && collection?
      child_resource(name, false, false, init_block, &block)
    end

    def child_resource(name, singleton, collection, init_block, &block)
       Resource.new(@sinatra, name, singleton, collection, self, init_block)
        .tap{|r| r.instance_eval(&block)}
        .tap{|r| @resources << r}
    end

    def instance_variable_name
      if @name
        @name.to_s.send(collection? ? :pluralize : :singularize).to_sym
      elsif member? && @parent
        @parent.name.to_s.singularize.to_sym
      else
        nil
      end
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
      sinatra.instance_exec(&@__init)
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
      response = sinatra.instance_variable_get("@#{self.instance_variable_name}")
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
      data = if response && collection? && method != :post
        response.to_a.map{|e| sinatra.instance_exec(e, &@__serialize) }
      else
        sinatra.instance_exec(response, &@__serialize)
      end

      {data: data, ok: true}
    end

    def sinatra_response_create_error(sinatra, response, method)
      errors = response.is_a?(ActiveModel::Errors) ? response : response.errors

      data = errors.to_hash.inject({}) do |memo, e|
        memo[e[0]] = e[1][0]
        memo
      end

      {data: data, ok: false}
    end

    def create_sinatra_route(method, action, &block)
      @actions << {method: method, action: action, block: block}

      resource = self

      route = resource.route({}, action)
      puts "sinatra router [#{method}] #{@sinatra.nested_config[:prefix]}#{route}"

      @sinatra.send(method, route) do
        content_type :json

        resource.self_and_parents.reverse.each do |res|
          res.sinatra_init(self)
        end

        resource.send(:"sinatra_exec_#{method}_block", self, &block)

        resource.sinatra_response(self, method)
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
        route = "#{self.nested_config[:prefix]}" + resource.route(route_args, action)
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

      js << "angular.module('#{module_name}', [])"
      js << ".factory('#{resource.name.to_s.camelcase.capitalize}#{nested_angular_config[:service_suffix]}', function($http, $q){"

      js << "  var impl = {}"
      angular_add_functions(js, resource)
      js << "  return impl"

      js << "})"

      get "/#{resource.name}.js" do
        content_type :js
        js.join("\n")
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
