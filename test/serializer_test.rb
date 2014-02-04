require "test/unit"
require "mocha/setup"
require "active_support/all"
require "active_model/errors"
require "active_record"
require "nested"

class SerializerTest < Test::Unit::TestCase

  def test_initialize
    assert_equal [], Nested::Serializer.new.includes
    assert_equal [], Nested::Serializer.new.excludes

    assert_equal [1,2,3], Nested::Serializer.new([1,2,3]).includes
  end

  def test_operator_plus
    ser = Nested::Serializer.new
    assert_equal ser, ser + :name
    assert_equal 1, ser.includes.length
    assert_equal :name, ser.includes[0].name
  end

  def test_operator_minus
    ser = Nested::Serializer.new([:name])
    assert_equal ser, ser - :name
    assert_equal 1, ser.excludes.length
    assert_equal :name, ser.excludes[0].name
  end

  def test_serialize
    ser = Nested::Serializer.new()
    ser + :id

    obj = {id: 2, name: "joe"}

    assert_equal({id: 2}, obj.instance_eval(&ser.serialize))

    ser + :name
    assert_equal({id: 2, name: "joe"}, obj.instance_eval(&ser.serialize))
  end

  def test_serialize_with_symbolize_keys
    ser = Nested::Serializer.new()
    ser + :id

    obj = {"id" => 2, "name" => "joe"}

    assert_equal({id: 2}, obj.instance_eval(&ser.serialize))

    ser + :name
    assert_equal({id: 2, name: "joe"}, obj.instance_eval(&ser.serialize))
  end

end
