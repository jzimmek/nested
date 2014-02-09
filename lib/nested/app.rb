module Nested
  class App
    def self.inherited(clazz)
      (class << clazz; self; end).instance_eval do
        attr_accessor :sinatra, :behaviors, :conditions
      end
      clazz.sinatra = Class.new(Sinatra::Base)
      clazz.instance_variable_set("@config", {})
      clazz.instance_variable_set("@behaviors", {})
      clazz.instance_variable_set("@conditions", {})
    end

    def self.behavior(name, &block)
      @behaviors[name] = block
      self
    end

    def self.condition(name, block)
      @conditions[name] = block

      @sinatra.send(:define_method, :"#{name}?") do
        instance_exec(&block)
      end

      self
    end

    def self.child_resource(name, clazz, resource_if_block, model_block, &block)
       clazz.new(self, sinatra, name, nil, resource_if_block, model_block)
            .tap{|r| r.instance_eval(&(block||Proc.new{ }))}
    end

    def self.before(&block)
      sinatra.before(&block)
      self
    end

    def self.after(&block)
      sinatra.after(&block)
      self
    end

    def self.config(opts={})
      @config.tap{|c| c.merge!(opts)}
    end

    extend WithSingleton
    extend WithMany
  end
end