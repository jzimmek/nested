require "test/unit"
require "mocha/setup"
require "active_support/all"
require "active_model/errors"
require "active_record"
require "nested"

class NestedTest < Test::Unit::TestCase

  def singleton!
    @r = Nested::Resource.new(@sinatra, :project, true, false, nil, nil)
  end

  def collection!
    @r = Nested::Resource.new(@sinatra, :project, false, true, nil, nil)
  end

  def member!
    @r = Nested::Resource.new(@sinatra, :project, false, false, nil, nil)
  end

  def setup
    @sinatra = mock
  end

  def test_initialize_name
    assert_raise Nested::NameMissingError do
      Nested::Resource.new({}, nil, true, false, nil, nil)
    end

    assert_raise Nested::NameMissingError do
      Nested::Resource.new({}, nil, false, true, nil, nil)
    end
  end

  def test_is_singleton
    singleton!
    assert_equal true, @r.singleton?

    collection!
    assert_equal false, @r.singleton?
  end

  def test_is_collection
    collection!
    assert_equal true, @r.collection?

    singleton!
    assert_equal false, @r.collection?
  end

  def test_is_member
    member!
    assert_equal true, @r.member?

    singleton!
    assert_equal false, @r.member?

    collection!
    assert_equal false, @r.member?
  end

  def test_init
    singleton!

    init = -> { }
    @r.init &init

    assert_equal init, @r.instance_variable_get("@__init")
  end

  def test_serialize
    singleton!

    @r.serialize :name

    assert_equal({name: :joe}, @r.instance_variable_get("@__serialize").call({name: :joe, test: true}))
  end

  def test_route
    # no parent
    singleton!
    assert_equal "/project", @r.route

    collection!
    assert_equal "/projects", @r.route

    member!
    assert_equal "/projects/:project_id", @r.route
    assert_equal "/projects/1", @r.route(project_id: 1)

    member!
    assert_equal "/projects/:project_id/myaction", @r.route({}, :myaction)
    assert_equal "/projects/1/myaction", @r.route({project_id: 1}, :myaction)

    # --- singleton

    singleton!
    @r2 = @r.singleton(:statistic) { }
    assert_equal "/project/statistic", @r2.route

    singleton!
    @r2 = @r.many(:statistics) { }
    assert_equal "/project/statistics", @r2.route

    singleton!
    @r2 = @r.one(:statistic) { }
    assert_equal "/project/statistics/:statistic_id", @r2.route
    assert_equal "/project/statistics/1", @r2.route(statistic_id: 1)

    # --- collection

    collection!
    @r2 = @r.singleton(:statistic) { }
    assert_equal "/projects/statistic", @r2.route

    collection!
    @r2 = @r.one { }
    assert_equal "/projects/:project_id", @r2.route
    assert_equal "/projects/1", @r2.route(project_id: 1)

    # --- member

    member!
    @r2 = @r.singleton(:statistic) { }
    assert_equal "/projects/:project_id/statistic", @r2.route
    assert_equal "/projects/1/statistic", @r2.route(project_id: 1)

    member!
    @r2 = @r.many(:statistic) { }
    assert_equal "/projects/:project_id/statistics", @r2.route
    assert_equal "/projects/1/statistics", @r2.route(project_id: 1)

    member!
    @r2 = @r.one(:statistic) { }
    assert_equal "/projects/:project_id/statistics/:statistic_id", @r2.route
    assert_equal "/projects/1/statistics/2", @r2.route(project_id: 1, statistic_id: 2)
  end


  def test_singleton
    singleton!
    @r.expects(:child_resource).with(:statistic, true, false, nil)
    @r.singleton(:statistic)

    member!
    @r.expects(:child_resource).with(:statistic, true, false, nil)
    @r.singleton(:statistic)

    collection!
    @r.expects(:child_resource).with(:statistic, true, false, nil)
    @r.singleton(:statistic)
  end

  def test_one
    singleton!
    @r.expects(:child_resource).with(:statistic, false, false, nil)
    @r.one(:statistic)

    member!
    @r.expects(:child_resource).with(:statistic, false, false, nil)
    @r.one(:statistic)

    collection!
    @r.expects(:child_resource).with(nil, false, false, nil)
    @r.one

    collection!
    assert_raise ::Nested::OneWithNameInManyError do
      @r.one :statistic
    end
  end

  def test_many
    singleton!
    @r.expects(:child_resource).with(:statistics, false, true, nil)
    @r.many(:statistics)

    member!
    @r.expects(:child_resource).with(:statistics, false, true, nil)
    @r.many(:statistics)

    collection!
    assert_raise ::Nested::ManyInManyError do
      @r.many :statistic
    end
  end

  def test_get
    singleton!

    @r.expects(:create_sinatra_route).with(:get, nil)
    @r.get

    @r.expects(:create_sinatra_route).with(:get, :action)
    @r.get :action
  end

  def test_post
    singleton!

    @r.expects(:create_sinatra_route).with(:post, nil)
    @r.post

    @r.expects(:create_sinatra_route).with(:post, :action)
    @r.post :action
  end

  def test_put
    singleton!

    @r.expects(:create_sinatra_route).with(:put, nil)
    @r.put

    @r.expects(:create_sinatra_route).with(:put, :action)
    @r.put :action
  end

  def test_delete
    singleton!

    @r.expects(:create_sinatra_route).with(:delete, nil)
    @r.delete

    @r.expects(:create_sinatra_route).with(:delete, :action)
    @r.delete :action
  end

  def test_child_resource
    singleton!
    r = @r.child_resource(:statistic, false, false, nil) { }
    assert_equal :statistic, r.name
    assert_equal false, r.instance_variable_get("@singleton")
    assert_equal false, r.instance_variable_get("@collection")

    singleton!
    r = @r.child_resource(:statistic, true, false, nil) { }
    assert_equal :statistic, r.name
    assert_equal true, r.instance_variable_get("@singleton")
    assert_equal false, r.instance_variable_get("@collection")

    singleton!
    r = @r.child_resource(:statistic, false, true, nil) { }
    assert_equal :statistic, r.name
    assert_equal false, r.instance_variable_get("@singleton")
    assert_equal true, r.instance_variable_get("@collection")

    singleton!
    assert_raise Nested::SingletonAndCollectionError do
      @r.child_resource(:statistic, true, true, nil) { }
    end
  end

  def test_instance_variable_name
    singleton!
    assert_equal :project, @r.instance_variable_name

    member!
    assert_equal :project, @r.instance_variable_name

    collection!
    assert_equal :projects, @r.instance_variable_name

    collection!
    r2 = @r.one {}
    assert_equal :project, r2.instance_variable_name
  end

  def test_parents
    singleton!
    assert_equal [], @r.parents

    r2 = @r.singleton(:statistic) { }
    assert_equal [@r], r2.parents

    r3 = r2.singleton(:statistic) { }
    assert_equal [@r, r2], r3.parents
  end

  def test_self_and_parents
    singleton!
    assert_equal [@r], @r.self_and_parents

    r2 = @r.singleton(:statistic) { }
    assert_equal [r2, @r], r2.self_and_parents

    r3 = r2.singleton(:statistic) { }
    assert_equal [r3, r2, @r], r3.self_and_parents
  end

  def test_create_sinatra_route
    @sinatra.expects(:nested_config).at_least_once.returns({})

    singleton!

    @sinatra.expects(:send).with(:get, "/project")
    block = ->{ }
    @r.create_sinatra_route(:get, nil, &block)
    assert_equal [{method: :get, action: nil, block: block}], @r.actions

    singleton!

    @sinatra.expects(:send).with(:post, "/project")
    @r.create_sinatra_route(:post, nil, &block)
    assert_equal [{method: :post, action: nil, block: block}], @r.actions

    singleton!

    @sinatra.expects(:send).with(:post, "/project/action")
    @r.create_sinatra_route(:post, :action, &block)
    assert_equal [{method: :post, action: :action, block: block}], @r.actions
  end

  def test_serializer
    singleton!
    # assert_equal(@r.serializer, Nested::Resource::SERIALIZE)

    ser = ->(obj) { obj }
    @r.serialize &ser

    assert_equal 1, @r.instance_variable_get("@__serialize").call(1)
  end

  # ----

  def test_sinatra_response_type
    singleton!
    assert_equal :error, @r.sinatra_response_type(ActiveModel::Errors.new({}))

    obj = OpenStruct.new(errors: ActiveModel::Errors.new({}))
    assert_equal :data, @r.sinatra_response_type(obj)

    obj.errors.add(:somefield, "some error")
    assert_equal :error, @r.sinatra_response_type(obj)

    assert_equal :data, @r.sinatra_response_type(nil)
    assert_equal :data, @r.sinatra_response_type(123)
  end


  # ----


  def test_function_name
    singleton!
    assert_equal "project", Nested::JsUtil::generate_function_name(@r, :get, nil)
    assert_equal "updateProject", Nested::JsUtil::generate_function_name(@r, :put, nil)
    assert_equal "createProject", Nested::JsUtil::generate_function_name(@r, :post, nil)
    assert_equal "destroyProject", Nested::JsUtil::generate_function_name(@r, :delete, nil)

    assert_equal "projectAction", Nested::JsUtil::generate_function_name(@r, :get, :action)
    assert_equal "updateProjectAction", Nested::JsUtil::generate_function_name(@r, :put, :action)
    assert_equal "createProjectAction", Nested::JsUtil::generate_function_name(@r, :post, :action)
    assert_equal "destroyProjectAction", Nested::JsUtil::generate_function_name(@r, :delete, :action)

    collection!
    assert_equal "projects", Nested::JsUtil::generate_function_name(@r, :get, nil)
    assert_equal "updateProjects", Nested::JsUtil::generate_function_name(@r, :put, nil)
    assert_equal "createProject", Nested::JsUtil::generate_function_name(@r, :post, nil)
    assert_equal "destroyProjects", Nested::JsUtil::generate_function_name(@r, :delete, nil)

    assert_equal "projectsAction", Nested::JsUtil::generate_function_name(@r, :get, :action)
    assert_equal "updateProjectsAction", Nested::JsUtil::generate_function_name(@r, :put, :action)
    assert_equal "createProjectAction", Nested::JsUtil::generate_function_name(@r, :post, :action)
    assert_equal "destroyProjectsAction", Nested::JsUtil::generate_function_name(@r, :delete, :action)

    member!
    assert_equal "project", Nested::JsUtil::generate_function_name(@r, :get, nil)
    assert_equal "updateProject", Nested::JsUtil::generate_function_name(@r, :put, nil)
    assert_equal "createProject", Nested::JsUtil::generate_function_name(@r, :post, nil)
    assert_equal "destroyProject", Nested::JsUtil::generate_function_name(@r, :delete, nil)

    assert_equal "projectAction", Nested::JsUtil::generate_function_name(@r, :get, :action)
    assert_equal "updateProjectAction", Nested::JsUtil::generate_function_name(@r, :put, :action)
    assert_equal "createProjectAction", Nested::JsUtil::generate_function_name(@r, :post, :action)
    assert_equal "destroyProjectAction", Nested::JsUtil::generate_function_name(@r, :delete, :action)


    # with parent

    singleton!

    r2 = @r.singleton(:statistic) {}

    assert_equal "projectStatistic", Nested::JsUtil::generate_function_name(r2, :get, nil)
    assert_equal "updateProjectStatistic", Nested::JsUtil::generate_function_name(r2, :put, nil)
    assert_equal "createProjectStatistic", Nested::JsUtil::generate_function_name(r2, :post, nil)
    assert_equal "destroyProjectStatistic", Nested::JsUtil::generate_function_name(r2, :delete, nil)

    assert_equal "projectStatisticAction", Nested::JsUtil::generate_function_name(r2, :get, :action)
    assert_equal "updateProjectStatisticAction", Nested::JsUtil::generate_function_name(r2, :put, :action)
    assert_equal "createProjectStatisticAction", Nested::JsUtil::generate_function_name(r2, :post, :action)
    assert_equal "destroyProjectStatisticAction", Nested::JsUtil::generate_function_name(r2, :delete, :action)

    member!

    r2 = @r.singleton(:statistic) {}

    assert_equal "projectStatistic", Nested::JsUtil::generate_function_name(r2, :get, nil)
    assert_equal "updateProjectStatistic", Nested::JsUtil::generate_function_name(r2, :put, nil)
    assert_equal "createProjectStatistic", Nested::JsUtil::generate_function_name(r2, :post, nil)
    assert_equal "destroyProjectStatistic", Nested::JsUtil::generate_function_name(r2, :delete, nil)

    assert_equal "projectStatisticAction", Nested::JsUtil::generate_function_name(r2, :get, :action)
    assert_equal "updateProjectStatisticAction", Nested::JsUtil::generate_function_name(r2, :put, :action)
    assert_equal "createProjectStatisticAction", Nested::JsUtil::generate_function_name(r2, :post, :action)
    assert_equal "destroyProjectStatisticAction", Nested::JsUtil::generate_function_name(r2, :delete, :action)

    collection!

    r2 = @r.singleton(:statistic) {}

    assert_equal "projectsStatistic", Nested::JsUtil::generate_function_name(r2, :get, nil)
    assert_equal "updateProjectsStatistic", Nested::JsUtil::generate_function_name(r2, :put, nil)
    assert_equal "createProjectStatistic", Nested::JsUtil::generate_function_name(r2, :post, nil)
    assert_equal "destroyProjectsStatistic", Nested::JsUtil::generate_function_name(r2, :delete, nil)

    assert_equal "projectsStatisticAction", Nested::JsUtil::generate_function_name(r2, :get, :action)
    assert_equal "updateProjectsStatisticAction", Nested::JsUtil::generate_function_name(r2, :put, :action)
    assert_equal "createProjectStatisticAction", Nested::JsUtil::generate_function_name(r2, :post, :action)
    assert_equal "destroyProjectsStatisticAction", Nested::JsUtil::generate_function_name(r2, :delete, :action)

    singleton!

    r2 = @r.many(:statistics) {}
    r3 = r2.one {}

    assert_equal "projectStatistic", Nested::JsUtil::generate_function_name(r3, :get, nil)
    assert_equal "updateProjectStatistic", Nested::JsUtil::generate_function_name(r3, :put, nil)
    assert_equal "createProjectStatistic", Nested::JsUtil::generate_function_name(r3, :post, nil)
    assert_equal "destroyProjectStatistic", Nested::JsUtil::generate_function_name(r3, :delete, nil)

    assert_equal "projectStatisticAction", Nested::JsUtil::generate_function_name(r3, :get, :action)
    assert_equal "updateProjectStatisticAction", Nested::JsUtil::generate_function_name(r3, :put, :action)
    assert_equal "createProjectStatisticAction", Nested::JsUtil::generate_function_name(r3, :post, :action)
    assert_equal "destroyProjectStatisticAction", Nested::JsUtil::generate_function_name(r3, :delete, :action)


    singleton!
    r2 = @r.many(:statistics) {}
    assert_equal "createProjectStatistic", Nested::JsUtil::generate_function_name(r2, :post, nil)


    singleton!
    r2 = @r.many(:statistics) {}
    r3 = r2.singleton(:user) {}

    assert_equal "projectStatisticsUser", Nested::JsUtil::generate_function_name(r3, :get, nil)

    singleton!
    r2 = @r.many(:statistics) {}
    r3 = r2.one {}
    r4 = r3.singleton(:user) {}

    assert_equal "projectStatisticUser", Nested::JsUtil::generate_function_name(r4, :get, nil)
  end

  # -----------------

  def test_function_arguments
    # --- singleton
    singleton!
    assert_equal [], Nested::JsUtil.function_arguments(@r)

    singleton!
    assert_equal [], Nested::JsUtil.function_arguments(@r.singleton(:statistic) {})

    singleton!
    assert_equal [], Nested::JsUtil.function_arguments(@r.many(:statistics) {})

    singleton!
    assert_equal ["statistic"], Nested::JsUtil.function_arguments(@r.one(:statistic) {})

    singleton!
    r2 = @r.one(:statistic) {}
    r3 = r2.singleton(:test) {}
    assert_equal ["statistic"], Nested::JsUtil.function_arguments(r3)

    # --- member

    member!
    assert_equal ["project"], Nested::JsUtil.function_arguments(@r)

    member!
    assert_equal ["project"], Nested::JsUtil.function_arguments(@r.singleton(:statistic) {})

    member!
    assert_equal ["project"], Nested::JsUtil.function_arguments(@r.many(:statistics) {})

    member!
    assert_equal ["project", "statistic"], Nested::JsUtil.function_arguments(@r.one(:statistic) {})

    # --- collection

    collection!
    assert_equal [], Nested::JsUtil.function_arguments(@r)

    collection!
    assert_equal [], Nested::JsUtil.function_arguments(@r.singleton(:statistic) {})

    collection!
    assert_equal ["project"], Nested::JsUtil.function_arguments(@r.one {})

    collection!
    r2 = @r.one {}
    r3 = r2.one(:statistic) {}

    assert_equal ["project", "statistic"], Nested::JsUtil.function_arguments(r3)
  end

end