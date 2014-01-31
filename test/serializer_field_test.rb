require "test/unit"
require "mocha/setup"
require "active_support/all"
require "active_model/errors"
require "active_record"
require "nested"

class SerializerFieldTest < Test::Unit::TestCase
  def test_initialize
    assert_equal :name, Nested::SerializerField.new(:name, :condition).name
    assert_equal :condition, Nested::SerializerField.new(:name, :condition).condition
  end
end
