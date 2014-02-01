module Nested
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