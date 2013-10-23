require "test/unit"
require "mocha/setup"
require "active_support/all"
require "nested"

class NestedTest < Test::Unit::TestCase

  def singleton!
    @r = Nested::Resource.new(@sinatra, :project, true, false, nil)
  end

  def collection!
    @r = Nested::Resource.new(@sinatra, :project, false, true, nil)
  end

  def member!
    @r = Nested::Resource.new(@sinatra, :project, false, false, nil)
  end

  def setup
    @sinatra = mock
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

  def test_fetch
    singleton!

    fetch = -> { }
    @r.fetch &fetch

    assert_equal(fetch, @r.instance_variable_get("@__fetch"))
  end

  def test_fetch_object
    singleton!

    Nested::Resource::FETCH.expects(:call).with(@r, {})
    @r.fetch_object({})

    fetch = -> { }
    @r.fetch &fetch

    fetch.expects(:call).with(@r, {})
    @r.fetch_object({})
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
    @r.expects(:child_resource).with(:statistic, true, false)
    @r.singleton(:statistic)

    member!
    @r.expects(:child_resource).with(:statistic, true, false)
    @r.singleton(:statistic)

    collection!
    @r.expects(:child_resource).with(:statistic, true, false)
    @r.singleton(:statistic)
  end

  def test_one
    singleton!
    @r.expects(:child_resource).with(:statistic, false, false)
    @r.one(:statistic)

    member!
    @r.expects(:child_resource).with(:statistic, false, false)
    @r.one(:statistic)

    collection!
    @r.expects(:child_resource).with(nil, false, false)
    @r.one

    collection!
    assert_raise ::Nested::OneWithNameInManyError do
      @r.one :statistic
    end
  end

  def test_many
    singleton!
    @r.expects(:child_resource).with(:statistics, false, true)
    @r.many(:statistics)

    member!
    @r.expects(:child_resource).with(:statistics, false, true)
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
    r = @r.child_resource(:statistic, false, false) { }
    assert_equal :statistic, r.name
    assert_equal false, r.instance_variable_get("@singleton")
    assert_equal false, r.instance_variable_get("@collection")

    singleton!
    r = @r.child_resource(:statistic, true, false) { }
    assert_equal :statistic, r.name
    assert_equal true, r.instance_variable_get("@singleton")
    assert_equal false, r.instance_variable_get("@collection")

    singleton!
    r = @r.child_resource(:statistic, false, true) { }
    assert_equal :statistic, r.name
    assert_equal false, r.instance_variable_get("@singleton")
    assert_equal true, r.instance_variable_get("@collection")

    singleton!
    assert_raise Nested::SingletonAndCollectionError do
      @r.child_resource(:statistic, true, true) { }
    end
  end

  def test_instance_variable_name
    singleton!
    assert_equal :project, @r.instance_variable_name

    member!
    assert_equal :project, @r.instance_variable_name

    collection!
    assert_equal :projects, @r.instance_variable_name
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
    @r.create_sinatra_route(:get, nil) { }
    assert_equal [{method: :get, action: nil}], @r.actions

    singleton!

    @sinatra.expects(:send).with(:post, "/project")
    @r.create_sinatra_route(:post, nil) { }
    assert_equal [{method: :post, action: nil}], @r.actions

    singleton!

    @sinatra.expects(:send).with(:post, "/project/action")
    @r.create_sinatra_route(:post, :action) { }
    assert_equal [{method: :post, action: :action}], @r.actions
  end

  # ----




  def test_function_name
    singleton!
    assert_equal "get", Nested::JsUtil::generate_function_name(@r, :get, nil)
    assert_equal "actionGet", Nested::JsUtil::generate_function_name(@r, :get, :action)

    collection!
    assert_equal "get", Nested::JsUtil::generate_function_name(@r, :get, nil)
    assert_equal "actionGet", Nested::JsUtil::generate_function_name(@r, :get, :action)

    member!
    assert_equal "get", Nested::JsUtil::generate_function_name(@r, :get, nil)
    assert_equal "actionGet", Nested::JsUtil::generate_function_name(@r, :get, :action)

    # delete -> destroy

    singleton!
    assert_equal "destroy", Nested::JsUtil::generate_function_name(@r, :delete, nil)
    assert_equal "actionDestroy", Nested::JsUtil::generate_function_name(@r, :delete, :action)

    # action

    singleton!
    assert_equal "myActionGet", Nested::JsUtil::generate_function_name(@r, :get, :my_action)

    collection!
    assert_equal "myActionGet", Nested::JsUtil::generate_function_name(@r, :get, :my_action)

    member!
    assert_equal "myActionGet", Nested::JsUtil::generate_function_name(@r, :get, :my_action)

    singleton!

    @sinatra.expects(:nested_config).returns({})
    @sinatra.expects(:get)
    @r2 = @r.singleton(:statistic) { get }

    assert_equal "statisticGet", Nested::JsUtil::generate_function_name(@r2, :get, nil)

    member!

    @sinatra.expects(:nested_config).returns({})
    @sinatra.expects(:get)
    @r2 = @r.singleton(:statistic) { get }

    assert_equal "statisticGet", Nested::JsUtil::generate_function_name(@r2, :get, nil)

    collection!

    @sinatra.expects(:nested_config).returns({})
    @sinatra.expects(:get)
    @r2 = @r.singleton(:statistic) { get }

    assert_equal "statisticGet", Nested::JsUtil::generate_function_name(@r2, :get, nil)
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