module Nested
  PROC_TRUE = Proc.new{ true }
  PROC_NIL = Proc.new{ nil }
end

require "json"
require "sinatra/base"

require "nested/js"

require "nested/redirect"

require "nested/with_many"
require "nested/with_singleton"
require "nested/with_model_block"

require "nested/resource"

require "nested/one"
require "nested/singleton"
require "nested/many"

require "nested/serializer"
require "nested/serializer_field"

require "nested/app"

require "nested/integration/angular"