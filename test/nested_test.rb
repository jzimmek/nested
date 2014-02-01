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

  def test_initialize_name
    assert_raise Nested::NameMissingError do
      Nested::Resource.new({}, nil, true, false, nil, Nested::Resource::PROC_TRUE, nil)
    end

    assert_raise Nested::NameMissingError do
      Nested::Resource.new({}, nil, false, true, nil, Nested::Resource::PROC_TRUE, nil)
    end
  end

  def test_is_singleton
    assert_equal true, singleton(:project).singleton?
    assert_equal false, many(:projects).singleton?
    assert_equal false, many(:projects).one.singleton?
  end

  def test_is_collection
    assert_equal true, many(:projects).collection?
    assert_equal false, many(:projects).one.collection?
    assert_equal false, singleton(:project).collection?
  end

  def test_is_member
    assert_equal true, many(:projects).one.member?
    assert_equal false, many(:projects).member?
    assert_equal false, singleton(:project).member?
  end

  def test_serialize
    serializer = mock()

    r = singleton(:project)
    r.stubs(:serializer).returns(serializer)

    assert_equal serializer, r.serialize

    serializer.expects(:+).with(:name)
    r.serialize :name
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
    resource.expects(:child_resource).with(:statistic, true, false, Nested::Resource::PROC_TRUE, nil)
    resource.singleton(:statistic)

    resource = many(:projects)
    resource.expects(:child_resource).with(:statistic, true, false, Nested::Resource::PROC_TRUE, nil)
    resource.singleton(:statistic)

    resource = many(:projects).one
    resource.expects(:child_resource).with(:statistic, true, false, Nested::Resource::PROC_TRUE, nil)
    resource.singleton(:statistic)
  end

  def test_one
    resource = many(:projects)
    resource.expects(:child_resource).with(:project, false, false, Nested::Resource::PROC_TRUE, nil)
    resource.one
  end

  def test_many
    resource = singleton(:project)
    resource.expects(:child_resource).with(:statistics, false, true, Nested::Resource::PROC_TRUE, nil)
    resource.many(:statistics)

    resource = singleton(:project).many(:statistics).one
    resource.expects(:child_resource).with(:entries, false, true, Nested::Resource::PROC_TRUE, nil)
    resource.many(:entries)
  end

  def test_get
    resource = singleton(:project)

    resource.expects(:create_sinatra_route).with(:get, nil)
    resource.get

    resource.expects(:create_sinatra_route).with(:get, :action)
    resource.get :action
  end

  def test_post
    resource = singleton(:project)

    resource.expects(:create_sinatra_route).with(:post, nil)
    resource.post

    resource.expects(:create_sinatra_route).with(:post, :action)
    resource.post :action
  end

  def test_put
    resource = singleton(:project)

    resource.expects(:create_sinatra_route).with(:put, nil)
    resource.put

    resource.expects(:create_sinatra_route).with(:put, :action)
    resource.put :action
  end

  def test_delete
    resource = singleton(:project)

    resource.expects(:create_sinatra_route).with(:delete, nil)
    resource.delete

    resource.expects(:create_sinatra_route).with(:delete, :action)
    resource.delete :action
  end

  def test_child_resource
    resource = singleton(:project).child_resource(:statistic, false, false, Proc.new{ true}, nil) { }
    assert_equal :statistic, resource.name
    assert_equal false, resource.instance_variable_get("@singleton")
    assert_equal false, resource.instance_variable_get("@collection")

    resource = singleton(:project).child_resource(:statistic, true, false, Proc.new{ true}, nil) { }
    assert_equal :statistic, resource.name
    assert_equal true, resource.instance_variable_get("@singleton")
    assert_equal false, resource.instance_variable_get("@collection")

    resource = singleton(:project).child_resource(:statistic, false, true, Proc.new{ true}, nil) { }
    assert_equal :statistic, resource.name
    assert_equal false, resource.instance_variable_get("@singleton")
    assert_equal true, resource.instance_variable_get("@collection")
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
    singleton(:project).get

    @sinatra.expects(:send).with(:get, "/project/action")
    singleton(:project).get(:action)

    # post

    @sinatra.expects(:send).with(:post, "/project")
    singleton(:project).post

    @sinatra.expects(:send).with(:post, "/project/action")
    singleton(:project).post(:action)

    # put

    @sinatra.expects(:send).with(:put, "/project")
    singleton(:project).put

    @sinatra.expects(:send).with(:put, "/project/action")
    singleton(:project).put(:action)

    # delete

    @sinatra.expects(:send).with(:delete, "/project")
    singleton(:project).delete

    @sinatra.expects(:send).with(:delete, "/project/action")
    singleton(:project).delete(:action)
  end


  # def test_serializer
  #   singleton!

  #   @r.serialize :name

  #   assert_equal({name: "joe"}, @r.instance_variable_get("@__serialize").call({name: "joe"}))
  #   assert_equal({name: "joe"}, @r.instance_variable_get("@__serialize").call({name: "joe", boss: true}))
  #   assert_equal({name: "joe"}, @r.instance_variable_get("@__serialize").call(OpenStruct.new({name: "joe"})))

  #   @r.serialize :name, virtual: ->(o){ o[:name] + "!!" }
  #   assert_equal({name: "joe", virtual: "joe!!"}, @r.instance_variable_get("@__serialize").call({name: "joe"}))
  # end

  # # ----

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

    assert_equal "project", Nested::JsUtil::generate_function_name(resource, :get, nil)
    assert_equal "updateProject", Nested::JsUtil::generate_function_name(resource, :put, nil)
    assert_equal "createProject", Nested::JsUtil::generate_function_name(resource, :post, nil)
    assert_equal "destroyProject", Nested::JsUtil::generate_function_name(resource, :delete, nil)

    assert_equal "projectAction", Nested::JsUtil::generate_function_name(resource, :get, :action)
    assert_equal "updateProjectAction", Nested::JsUtil::generate_function_name(resource, :put, :action)
    assert_equal "createProjectAction", Nested::JsUtil::generate_function_name(resource, :post, :action)
    assert_equal "destroyProjectAction", Nested::JsUtil::generate_function_name(resource, :delete, :action)

    resource = many(:projects)

    assert_equal "projects", Nested::JsUtil::generate_function_name(resource, :get, nil)
    assert_equal "updateProjects", Nested::JsUtil::generate_function_name(resource, :put, nil)
    assert_equal "createProject", Nested::JsUtil::generate_function_name(resource, :post, nil)
    assert_equal "destroyProjects", Nested::JsUtil::generate_function_name(resource, :delete, nil)

    assert_equal "projectsAction", Nested::JsUtil::generate_function_name(resource, :get, :action)
    assert_equal "updateProjectsAction", Nested::JsUtil::generate_function_name(resource, :put, :action)
    assert_equal "createProjectAction", Nested::JsUtil::generate_function_name(resource, :post, :action)
    assert_equal "destroyProjectsAction", Nested::JsUtil::generate_function_name(resource, :delete, :action)

    resource = many(:projects).one

    assert_equal "project", Nested::JsUtil::generate_function_name(resource, :get, nil)
    assert_equal "updateProject", Nested::JsUtil::generate_function_name(resource, :put, nil)
    assert_equal "createProject", Nested::JsUtil::generate_function_name(resource, :post, nil)
    assert_equal "destroyProject", Nested::JsUtil::generate_function_name(resource, :delete, nil)

    assert_equal "projectAction", Nested::JsUtil::generate_function_name(resource, :get, :action)
    assert_equal "updateProjectAction", Nested::JsUtil::generate_function_name(resource, :put, :action)
    assert_equal "createProjectAction", Nested::JsUtil::generate_function_name(resource, :post, :action)
    assert_equal "destroyProjectAction", Nested::JsUtil::generate_function_name(resource, :delete, :action)

    resource = singleton(:project).many(:statistics)

    assert_equal "projectStatistics", Nested::JsUtil::generate_function_name(resource, :get, nil)
    assert_equal "updateProjectStatistics", Nested::JsUtil::generate_function_name(resource, :put, nil)
    assert_equal "createProjectStatistic", Nested::JsUtil::generate_function_name(resource, :post, nil)
    assert_equal "destroyProjectStatistics", Nested::JsUtil::generate_function_name(resource, :delete, nil)

    assert_equal "projectStatisticsAction", Nested::JsUtil::generate_function_name(resource, :get, :action)
    assert_equal "updateProjectStatisticsAction", Nested::JsUtil::generate_function_name(resource, :put, :action)
    assert_equal "createProjectStatisticAction", Nested::JsUtil::generate_function_name(resource, :post, :action)
    assert_equal "destroyProjectStatisticsAction", Nested::JsUtil::generate_function_name(resource, :delete, :action)

    resource = singleton(:project).many(:statistics).one

    assert_equal "projectStatistic", Nested::JsUtil::generate_function_name(resource, :get, nil)
    assert_equal "updateProjectStatistic", Nested::JsUtil::generate_function_name(resource, :put, nil)
    assert_equal "createProjectStatistic", Nested::JsUtil::generate_function_name(resource, :post, nil)
    assert_equal "destroyProjectStatistic", Nested::JsUtil::generate_function_name(resource, :delete, nil)

    assert_equal "projectStatisticAction", Nested::JsUtil::generate_function_name(resource, :get, :action)
    assert_equal "updateProjectStatisticAction", Nested::JsUtil::generate_function_name(resource, :put, :action)
    assert_equal "createProjectStatisticAction", Nested::JsUtil::generate_function_name(resource, :post, :action)
    assert_equal "destroyProjectStatisticAction", Nested::JsUtil::generate_function_name(resource, :delete, :action)

    resource = singleton(:project).many(:statistics).one.many(:entries)
    assert_equal "projectStatisticEntries", Nested::JsUtil::generate_function_name(resource, :get, nil)
  end

  def test_function_arguments
    assert_equal [], Nested::JsUtil.function_arguments(singleton(:project))
    assert_equal [], Nested::JsUtil.function_arguments(singleton(:project).singleton(:statistic))
    assert_equal [], Nested::JsUtil.function_arguments(singleton(:project).many(:statistics))
    assert_equal ["statistic"], Nested::JsUtil.function_arguments(singleton(:project).many(:statistics).one)

    assert_equal [], Nested::JsUtil.function_arguments(many(:projects))
    assert_equal [], Nested::JsUtil.function_arguments(many(:projects).singleton(:statistic))
    assert_equal ["project"], Nested::JsUtil.function_arguments(many(:projects).one)

    assert_equal ["project"], Nested::JsUtil.function_arguments(many(:projects).one.singleton(:today))
    assert_equal [], Nested::JsUtil.function_arguments(many(:projects).singleton(:statistic).singleton(:today))
    assert_equal ["project", "entry"], Nested::JsUtil.function_arguments(many(:projects).one.many(:entries).one)
  end

end