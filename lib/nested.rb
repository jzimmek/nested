module Nested

  class OneWithNameInManyError < StandardError
  end

  class ManyInManyError < StandardError
  end

  class SingletonAndCollectionError < StandardError
  end

  class Resource
    FETCH =  ->(resource, ctrl) do
      raise "implement fetch for resource #{resource.name}"  unless resource.parent
      raise "implement fetch for singleton #{resource.name}" if resource.singleton?

      parent_resource = resource.parent
      parent_obj = ctrl.instance_variable_get("@#{parent_resource.instance_variable_name}")

      if resource.name
        scope = parent_obj.send(resource.name.to_s.pluralize.to_sym)
        resource.collection? ? scope : scope.where(id: ctrl.params["#{resource.name.to_s.singularize}_id"]).first
      else
        parent_obj.where(id: ctrl.params["#{parent_resource.name.to_s.singularize}_id"]).first
      end
    end

    attr_reader :name, :parent, :actions, :resources

    def initialize(sinatra, name, singleton, collection, parent)
      raise SingletonAndCollectionError.new if singleton && collection

      @sinatra = sinatra
      @name = name
      @singleton = singleton
      @collection = collection
      @parent = parent
      @resources = []
      @actions = []
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

    def fetch(&block)
      @__fetch = block
    end

    def fetch_object(ctrl)
      (@__fetch || FETCH).call(self, ctrl)
    end

    def route(args={})
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
      end
    end

    def get(action=nil, &block)
      create_sinatra_route :get, action, &(block || get_default)
    end

    def get_default
      ->(resource) { instance_variable_get("@#{resource.instance_variable_name}") }
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

    def singleton(name, &block)
      child_resource(name, true, false, &block)
    end

    def many(name, &block)
      raise ManyInManyError.new "do not nest many in many" if collection?
      child_resource(name, false, true, &block)
    end

    def one(name=nil, &block)
      raise OneWithNameInManyError.new("call one (#{name}) without name argument when nested in a many (#{@name})") if name && collection?
      child_resource(name, false, false, &block)
    end

    def child_resource(name, singleton, collection, &block)
       Resource.new(@sinatra, name, singleton, collection, self)
        .tap{|r| r.instance_eval(&block)}
        .tap{|r| @resources << r}
    end

    def instance_variable_name
      @name.to_s.send(collection? ? :pluralize : :singularize).to_sym
    end

    def parents
      (@parent ? @parent.parents + [@parent] : [])
    end

    def self_and_parents
      (self.parents + [self]).reverse
    end

    def create_sinatra_route(method, action, &block)
      @actions << {method: method, actions: action}

      resource = self

      puts "sinatra router [#{method}] #{@sinatra.prefix}#{resource.route}"

      @sinatra.send(method, resource.route) do
        content_type :json

        resource.self_and_parents.reverse.each do |res|
          resource_obj = res.fetch_object(self)

          puts "set @#{res.instance_variable_name} to #{resource_obj.inspect} for #{self}"
          instance_variable_set("@#{res.instance_variable_name}", resource_obj)
        end

        case response = instance_exec(resource, &block)
          when String then  response
          else              response.to_json
        end
      end
    end
  end

  module Angular
    def self.extended(base)
      base.send(:extend, Nested::Angular::Sinatra)
    end

    module Sinatra
      def create_resource(name, singleton, collection, &block)
        angularize(super)
      end
    end

    def angular_add_functions(js, resource)
      resource.actions.each do |e|
        method, action = e.values_at :method, :action

        fun_name = Nested::JsUtil::generate_function_name(resource, method, action)

        args = Nested::JsUtil::function_arguments(resource)

        route_args = args.inject({}) do |memo, e|
          idx = args.index(e)
          memo[:"#{e}_id"] = "'+(typeof(values[#{idx}]) == 'number' ? values[#{idx}].toString() : values[#{idx}].id)+'"
          memo
        end
        route = "#{self.prefix}" + resource.route(route_args)

        js << "  impl.#{fun_name} = function(#{args.join(',')}){"

        args = args.map{|a| "$q.when(#{a})"}

        js << "    return $q.all([#{args.join(',')}]).then(function(values){" unless args.empty?
        js << (args.length > 1 ? "  " : "") + "    return $http({method: '#{method}', url: '#{route}'})"
        js << "    });" unless args.empty?

        js << "  }"
      end

      resource.resources.each {|r| angular_add_functions(js, r) }
    end

    def angularize(resource)
      js = []

      module_name = "nested_#{resource.name}".camelcase(:lower)

      js << "angular.module('#{module_name}', ['ngResource'])"
      js << ".factory('#{resource.name.to_s.camelcase.capitalize}Service', function($http, $q){"

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
        arr = resource.self_and_parents

        fun_name_arr = arr
                        .reject{|r| r == arr.last }
                        .map{|r| r.name || :one}
                        .reverse

        fun_name_arr << action if action
        fun_name_arr << case method
          when :delete then :destroy
          else method
        end

        fun_name_arr.map(&:to_s).join("_").camelcase(:lower)
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
    def prefix(prefix=nil)
      if prefix
        @prefix = prefix
      else
        @prefix
      end
    end
    def singleton(name, &block)
      create_resource(name, true, false, &block)
    end
    def many(name, &block)
      create_resource(name, false, true, &block)
    end
    def one(name, &block)
      create_resource(name, false, false, &block)
    end
    def create_resource(name, singleton, collection, &block)
      ::Nested::Resource.new(self, name, singleton, collection, nil).tap{|r| r.instance_eval(&block) }
    end
  end

end
