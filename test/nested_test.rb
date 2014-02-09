require "test/unit"
require "mocha/setup"
require "active_support/all"
require "active_model/errors"
require "active_record"
require "nested"
require "./test/test_helper"

class NestedTest < Test::Unit::TestCase

  include TestHelper

  def setup
    @sinatra = mock
  end

  def test_initialize
    r = singleton(:project)

    assert_equal :project, r.name
    assert_equal nil, r.parent
    assert_equal [], r.resources
    assert_equal [], r.actions
    assert_equal Nested::PROC_NIL, r.model_block


    assert_equal [], r.before_blocks
    assert_equal [], r.after_blocks

    assert_equal Nested::Singleton::MODEL_BLOCK, singleton(:project, nil).model_block
    assert_equal Nested::Many::MODEL_BLOCK, many(:projects, nil).model_block
    assert_equal Nested::One::MODEL_BLOCK, many(:projects, nil).one.model_block

    assert_equal true, r.instance_variable_get("@app") <= Nested::App
  end

  def test_behave
    r = singleton(:project)
    a = r.instance_variable_get("@app")
    a.behavior :mybehavior do
      get
    end
    @sinatra.expects(:get)
    r.behave :mybehavior
  end

  def test_serialize
    serializer = mock()

    r = singleton(:project)
    r.stubs(:serializer).returns(serializer)

    assert_equal r, r.serialize

    serializer.expects(:+).with(:name)
    r.serialize :name
  end

  def test_before
    b = ->{}
    r = singleton(:project)
    assert_equal r, r.before(&b)
    assert_equal [b], r.before_blocks
  end

  def test_after
    b = ->{}
    r = singleton(:project)
    assert_equal r, r.after(&b)
    assert_equal [b], r.after_blocks
  end

  def test_model_block
    model_block = ->{ }
    r = singleton(:project)
    assert_equal r, r.model(model_block)
    assert_equal model_block, r.model_block
  end

  def test_route_replace
    resource = many(:projects).one

    assert_equal "/projects/1", resource.route_replace(resource.route, project_id: 1)
    assert_equal "/projects/1/myaction", resource.route_replace(resource.route(:myaction), project_id: 1)

    resource = singleton(:project).many(:statistics).one
    assert_equal "/project/statistics/1", resource.route_replace(resource.route, statistic_id: 1)

    resource = singleton(:project).many(:statistics).one.singleton(:today)
    assert_equal "/project/statistics/1/today", resource.route_replace(resource.route, statistic_id: 1)

    resource = singleton(:project).many(:statistics).one.many(:entries)
    assert_equal "/project/statistics/1/entries", resource.route_replace(resource.route, statistic_id: 1)

    resource = singleton(:project).many(:statistics).one.many(:entries).one
    assert_equal "/project/statistics/1/entries/2", resource.route_replace(resource.route, statistic_id: 1, entry_id: 2)
  end

  def test_route
    assert_equal "/project", singleton(:project).route
    assert_equal "/projects", many(:projects).route

    assert_equal "/projects/:project_id", many(:projects).one.route
    assert_equal "/projects/:project_id/myaction", many(:projects).one.route(:myaction)

    assert_equal "/project/statistic", singleton(:project).singleton(:statistic).route
    assert_equal "/project/statistics", singleton(:project).many(:statistics).route

    assert_equal "/project/statistics/:statistic_id", singleton(:project).many(:statistics).one.route
    assert_equal "/project/statistics/:statistic_id/today", singleton(:project).many(:statistics).one.singleton(:today).route

    assert_equal "/project/statistics/:statistic_id/entries", singleton(:project).many(:statistics).one.many(:entries).route
    assert_equal "/project/statistics/:statistic_id/entries/:entry_id", singleton(:project).many(:statistics).one.many(:entries).one.route
  end


  def test_singleton
    resource = singleton(:project)
    resource.expects(:child_resource).with(:statistic, Nested::Singleton, Nested::PROC_TRUE, nil)
    resource.singleton(:statistic)

    resource = many(:projects)
    resource.expects(:child_resource).with(:statistic, Nested::Singleton, Nested::PROC_TRUE, nil)
    resource.singleton(:statistic)

    resource = many(:projects).one
    resource.expects(:child_resource).with(:statistic, Nested::Singleton, Nested::PROC_TRUE, nil)
    resource.singleton(:statistic)
  end

  def test_one
    resource = many(:projects)
    resource.expects(:child_resource).with(:project, Nested::One, Nested::PROC_TRUE, nil)
    resource.one
  end

  def test_many
    resource = singleton(:project)
    resource.expects(:child_resource).with(:statistics, Nested::Many, Nested::PROC_TRUE, nil)
    resource.many(:statistics)

    resource = singleton(:project).many(:statistics).one
    resource.expects(:child_resource).with(:entries, Nested::Many, Nested::PROC_TRUE, nil)
    resource.many(:entries)
  end

  def test_get
    resource = singleton(:project)

    resource.expects(:create_sinatra_route).with(:get, nil, Nested::PROC_TRUE)
    resource.get

    resource.expects(:create_sinatra_route).with(:get, :action, Nested::PROC_TRUE)
    resource.get :action
  end

  def test_post
    resource = singleton(:project)

    resource.expects(:create_sinatra_route).with(:post, nil, Nested::PROC_TRUE)
    resource.post

    resource.expects(:create_sinatra_route).with(:post, :action, Nested::PROC_TRUE)
    resource.post :action
  end

  def test_put
    resource = singleton(:project)

    resource.expects(:create_sinatra_route).with(:put, nil, Nested::PROC_TRUE)
    resource.put

    resource.expects(:create_sinatra_route).with(:put, :action, Nested::PROC_TRUE)
    resource.put :action
  end

  def test_delete
    resource = singleton(:project)

    resource.expects(:create_sinatra_route).with(:delete, nil, Nested::PROC_TRUE)
    resource.delete

    resource.expects(:create_sinatra_route).with(:delete, :action, Nested::PROC_TRUE)
    resource.delete :action
  end

  def test_child_resource
    resource = many(:projects).child_resource(:statistic, Nested::One, Proc.new{ true}, nil) { }
    assert_equal :statistic, resource.name
    assert_equal true, resource.is_a?(Nested::One)

    resource = singleton(:project).child_resource(:statistic, Nested::Singleton, Proc.new{ true}, nil) { }
    assert_equal :statistic, resource.name
    assert_equal true, resource.is_a?(Nested::Singleton)

    resource = singleton(:project).child_resource(:statistic, Nested::Many, Proc.new{ true}, nil) { }
    assert_equal :statistic, resource.name
    assert_equal true, resource.is_a?(Nested::Many)
  end

  def test_instance_variable_name
    assert_equal :project, singleton(:project).instance_variable_name
    assert_equal :projects, many(:projects).instance_variable_name
    assert_equal :project, many(:projects).one.instance_variable_name
  end

  def test_parents
    r1 = singleton(:project)
    r2 = r1.many(:todos)
    r3 = r2.one

    assert_equal [], r1.parents
    assert_equal [r1], r2.parents
    assert_equal [r1, r2], r3.parents
  end

  def test_self_and_parents
    r1 = singleton(:project)
    r2 = r1.many(:todos)
    r3 = r2.one

    assert_equal [r1], r1.self_and_parents
    assert_equal [r2, r1], r2.self_and_parents
    assert_equal [r3, r2, r1], r3.self_and_parents
  end

  def test_create_sinatra_route
    # get

    @sinatra.expects(:send).with(:get, "/project")
    r = singleton(:project)
    assert_equal r, r.get

    @sinatra.expects(:send).with(:get, "/project/action")
    r = singleton(:project)
    assert_equal r, r.get(:action)

    # post

    @sinatra.expects(:send).with(:post, "/project")
    r = singleton(:project)
    assert_equal r, r.post

    @sinatra.expects(:send).with(:post, "/project/action")
    r = singleton(:project)
    assert_equal r, r.post(:action)

    # put

    @sinatra.expects(:send).with(:put, "/project")
    r = singleton(:project)
    assert_equal r, r.put

    @sinatra.expects(:send).with(:put, "/project/action")
    r = singleton(:project)
    assert_equal r, r.put(:action)

    # delete

    @sinatra.expects(:send).with(:delete, "/project")
    r = singleton(:project)
    assert_equal r, r.delete

    @sinatra.expects(:send).with(:delete, "/project/action")
    r = singleton(:project)
    assert_equal r, r.delete(:action)
  end


  def test_sinatra_response_type
    assert_equal :error, singleton(:project).sinatra_response_type(ActiveModel::Errors.new({}))

    obj = OpenStruct.new(errors: ActiveModel::Errors.new({}))
    assert_equal :data, singleton(:project).sinatra_response_type(obj)

    obj.errors.add(:somefield, "some error")
    assert_equal :error, singleton(:project).sinatra_response_type(obj)

    assert_equal :data, singleton(:project).sinatra_response_type(nil)
    assert_equal :data, singleton(:project).sinatra_response_type(123)
  end


  # # ----

  def test_function_name
    resource = singleton(:project)

    assert_equal "project", Nested::Js::generate_function_name(resource, :get, nil)
    assert_equal "updateProject", Nested::Js::generate_function_name(resource, :put, nil)
    assert_equal "createProject", Nested::Js::generate_function_name(resource, :post, nil)
    assert_equal "destroyProject", Nested::Js::generate_function_name(resource, :delete, nil)

    assert_equal "projectAction", Nested::Js::generate_function_name(resource, :get, :action)
    assert_equal "updateProjectAction", Nested::Js::generate_function_name(resource, :put, :action)
    assert_equal "createProjectAction", Nested::Js::generate_function_name(resource, :post, :action)
    assert_equal "destroyProjectAction", Nested::Js::generate_function_name(resource, :delete, :action)

    resource = many(:projects)

    assert_equal "projects", Nested::Js::generate_function_name(resource, :get, nil)
    assert_equal "updateProjects", Nested::Js::generate_function_name(resource, :put, nil)
    assert_equal "createProject", Nested::Js::generate_function_name(resource, :post, nil)
    assert_equal "destroyProjects", Nested::Js::generate_function_name(resource, :delete, nil)

    assert_equal "projectsAction", Nested::Js::generate_function_name(resource, :get, :action)
    assert_equal "updateProjectsAction", Nested::Js::generate_function_name(resource, :put, :action)
    assert_equal "createProjectAction", Nested::Js::generate_function_name(resource, :post, :action)
    assert_equal "destroyProjectsAction", Nested::Js::generate_function_name(resource, :delete, :action)

    resource = many(:projects).one

    assert_equal "project", Nested::Js::generate_function_name(resource, :get, nil)
    assert_equal "updateProject", Nested::Js::generate_function_name(resource, :put, nil)
    assert_equal "createProject", Nested::Js::generate_function_name(resource, :post, nil)
    assert_equal "destroyProject", Nested::Js::generate_function_name(resource, :delete, nil)

    assert_equal "projectAction", Nested::Js::generate_function_name(resource, :get, :action)
    assert_equal "updateProjectAction", Nested::Js::generate_function_name(resource, :put, :action)
    assert_equal "createProjectAction", Nested::Js::generate_function_name(resource, :post, :action)
    assert_equal "destroyProjectAction", Nested::Js::generate_function_name(resource, :delete, :action)

    resource = singleton(:project).many(:statistics)

    assert_equal "projectStatistics", Nested::Js::generate_function_name(resource, :get, nil)
    assert_equal "updateProjectStatistics", Nested::Js::generate_function_name(resource, :put, nil)
    assert_equal "createProjectStatistic", Nested::Js::generate_function_name(resource, :post, nil)
    assert_equal "destroyProjectStatistics", Nested::Js::generate_function_name(resource, :delete, nil)

    assert_equal "projectStatisticsAction", Nested::Js::generate_function_name(resource, :get, :action)
    assert_equal "updateProjectStatisticsAction", Nested::Js::generate_function_name(resource, :put, :action)
    assert_equal "createProjectStatisticAction", Nested::Js::generate_function_name(resource, :post, :action)
    assert_equal "destroyProjectStatisticsAction", Nested::Js::generate_function_name(resource, :delete, :action)

    resource = singleton(:project).many(:statistics).one

    assert_equal "projectStatistic", Nested::Js::generate_function_name(resource, :get, nil)
    assert_equal "updateProjectStatistic", Nested::Js::generate_function_name(resource, :put, nil)
    assert_equal "createProjectStatistic", Nested::Js::generate_function_name(resource, :post, nil)
    assert_equal "destroyProjectStatistic", Nested::Js::generate_function_name(resource, :delete, nil)

    assert_equal "projectStatisticAction", Nested::Js::generate_function_name(resource, :get, :action)
    assert_equal "updateProjectStatisticAction", Nested::Js::generate_function_name(resource, :put, :action)
    assert_equal "createProjectStatisticAction", Nested::Js::generate_function_name(resource, :post, :action)
    assert_equal "destroyProjectStatisticAction", Nested::Js::generate_function_name(resource, :delete, :action)

    resource = singleton(:project).many(:statistics).one.many(:entries)
    assert_equal "projectStatisticEntries", Nested::Js::generate_function_name(resource, :get, nil)
  end

  def test_function_arguments
    assert_equal [], Nested::Js.function_arguments(singleton(:project))
    assert_equal [], Nested::Js.function_arguments(singleton(:project).singleton(:statistic))
    assert_equal [], Nested::Js.function_arguments(singleton(:project).many(:statistics))
    assert_equal ["statistic"], Nested::Js.function_arguments(singleton(:project).many(:statistics).one)

    assert_equal [], Nested::Js.function_arguments(many(:projects))
    assert_equal [], Nested::Js.function_arguments(many(:projects).singleton(:statistic))
    assert_equal ["project"], Nested::Js.function_arguments(many(:projects).one)

    assert_equal ["project"], Nested::Js.function_arguments(many(:projects).one.singleton(:today))
    assert_equal [], Nested::Js.function_arguments(many(:projects).singleton(:statistic).singleton(:today))
    assert_equal ["project", "entry"], Nested::Js.function_arguments(many(:projects).one.many(:entries).one)
  end

  def test_sinatra_init
    @sinatra.stubs(:get)
    r = singleton(:project, ->{ {name: "joe"} }).get

    r.expects(:sinatra_init_set_resource).with(@sinatra)
    r.expects(:sinatra_init_before).with(@sinatra)
    r.expects(:sinatra_init_set_model).with(@sinatra)
    r.expects(:sinatra_init_after).with(@sinatra)

    r.sinatra_init(@sinatra)

    r.expects(:sinatra_init_set_resource).with(@sinatra)

    assert_raise RuntimeError do
      r.instance_variable_set("@resource_if_block", ->{ false })
      r.sinatra_init(@sinatra)
    end
  end

  def test_sinatra_init_set_resource
    @sinatra.stubs(:get)
    r = singleton(:project, ->{ {name: "joe"} }).get
    r.sinatra_init_set_resource(@sinatra)
    assert_equal r, @sinatra.instance_variable_get("@__resource")
  end

  def test_sinatra_init_set_model
    @sinatra.stubs(:get)
    @sinatra.instance_variable_set("@some_value", 10)
    r = singleton(:project, ->{ {name: "joe", some_value: @some_value} }).get
    r.sinatra_init_set_model(@sinatra)
    assert_equal ({name: "joe", some_value: 10}), @sinatra.instance_variable_get("@project")

    @sinatra.stubs(:get)
    @sinatra.instance_variable_set("@some_value", 10)
    @sinatra.instance_variable_set("@other_value", 2)

    r = singleton(:project, ->(default){ {name: "joe", some_value: @some_value * default} }).get
    r.stubs(:default_model_block).returns(->{ @other_value })
    r.sinatra_init_set_model(@sinatra)
    assert_equal ({name: "joe", some_value: 20}), @sinatra.instance_variable_get("@project")
  end

  def test_sinatra_init_before
    @sinatra.stubs(:get)
    before_called = false

    r = singleton(:project, ->{ {name: "joe"} }).get.before(&->{ before_called = true })
    r.sinatra_init_before(@sinatra)

    assert_equal true, before_called
  end

  def test_sinatra_init_after
    @sinatra.stubs(:get)
    after_called = false

    r = singleton(:project, ->{ {name: "joe"} }).get.after(&->{ after_called = true })
    r.sinatra_init_after(@sinatra)

    assert_equal true, after_called
  end

  def test_default_model_block
    assert_equal Nested::Singleton::MODEL_BLOCK, singleton(:project).default_model_block
    assert_equal Nested::Many::MODEL_BLOCK, many(:projects).default_model_block
    assert_equal Nested::One::MODEL_BLOCK, many(:projects).one.default_model_block
  end

  def test_model
    model_block = ->{}
    r = singleton(:project)
    assert_equal r, r.model(model_block)
    assert_equal model_block, r.instance_variable_get("@model_block")

    assert_raise RuntimeError do
      singleton(:project, ->{ 10 }).model(->{ 20 })
    end

    many(:projects, nil).model(model_block)
  end

  # def test_conditions
  #   r = singleton(:project)
  #   app = r.instance_variable_get("@app")
  #   app.condition :mycondition, ->{ true }
  #   assert_equal true, app.sinatra.new.mycondition?
  # end

end