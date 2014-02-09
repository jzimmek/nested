require "test/unit"
require "mocha/setup"
require "active_support/all"
require "active_model/errors"
require "active_record"
require "nested"
require "./test/test_helper"

class NestedTest < Test::Unit::TestCase

  include TestHelper

  def app
    Class.new(Nested::App)
  end

  def test_inherited
    a = app

    assert_equal ({}), a.instance_variable_get("@config")
    assert_equal ({}), a.instance_variable_get("@behaviors")
    assert_equal true, a.sinatra < Sinatra::Base
  end

  def test_behavior
    b = ->{}
    assert_equal ({:test => b}), app.behavior(:test, &b).instance_variable_get("@behaviors")
  end

  def test_condition
    b = ->{}
    assert_equal ({:test => b}), app.condition(:test, b).instance_variable_get("@conditions")
  end

  def test__before
    a = app

    sinatra = mock
    sinatra.expects(:before)

    a.instance_variable_set("@sinatra", sinatra)
    assert_equal a, a.before(&->{})
  end

  def test__after
    a = app

    sinatra = mock
    sinatra.expects(:after)

    a.instance_variable_set("@sinatra", sinatra)
    assert_equal a, a.after(&->{})
  end

  def test_config
    a = app
    assert_equal ({key1: true}), a.config(key1: true)
    assert_equal ({key1: true}), a.instance_variable_get("@config")
  end
end