module Nested
  module Integration
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

            fun_name = Nested::Js::generate_function_name(resource, method, action)

            args = Nested::Js::function_arguments(resource)

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
              js << "  impl.#{fun_name} = function(#{(args + ['data']).join(',')}){"
              js << "    var deferred = $q.defer()"
              js << "    $q.all([#{when_args.join(',')}]).then(function(values){"
              js << "      $http({"
              js << "         method: '#{method}', "
              js << "         url: '#{route}', "
              js << "         params: data||{}"
              js << "      })"
              js << "        .success(function(responseData){"
              js << "           deferred[responseData.ok ? 'resolve' : 'reject'](responseData.data)"
              js << "        })"
              js << "        .error(function(){ deferred.reject() })"
              js << "    });"
              js << "    return deferred.promise"
              js << "  }"

              # args << "data" if !block_args.empty?

              # js << "  impl.#{fun_name} = function(#{args.join(',')}){"
              # js << "    var deferred = $q.defer()"
              # js << "    $q.all([#{when_args.join(',')}]).then(function(values){"
              # js << "      $http({"
              # js << "         method: '#{method}', "
              # js << ("         url: '#{route}'" + (block_args.empty? ? "" : ","))
              # js << "         params: data" unless block_args.empty?
              # js << "      })"
              # js << "        .success(function(responseData){"
              # js << "           deferred[responseData.ok ? 'resolve' : 'reject'](responseData.data)"
              # js << "        })"
              # js << "        .error(function(){ deferred.reject() })"
              # js << "    });"
              # js << "    return deferred.promise"
              # js << "  }"
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
  end
end