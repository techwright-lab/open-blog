require_relative "test_helper"

class ApiBaseProbeController < OpenBlog::Api::V1::BaseController
  def index
    require_scope!(:read)
    render json: input_fields!(:value)
  end
end

class ApiBaseOtherProbeController < ApiBaseProbeController
end

class ApiBaseTest < ActionController::TestCase
  tests ApiBaseProbeController

  setup do
    @settings = %i[authenticate api_rate_limit rate_limit_store].to_h { |key| [ key, OpenBlog.config.public_send(key) ] }
    OpenBlog.config.authenticate = nil
    OpenBlog.config.api_rate_limit = { to: 2, within: 1.minute }
    OpenBlog.config.rate_limit_store = ActiveSupport::Cache::MemoryStore.new
    @routes = ActionDispatch::Routing::RouteSet.new
    @routes.draw { match "/probe", to: "api_base_probe#index", via: [ :get, :post ] }
  end
  teardown { @settings.each { |key, value| OpenBlog.config.public_send("#{key}=", value) } }

  test "authentication and scope errors are structured and never cached" do
    get :index
    assert_error 401, "unauthenticated", []
    OpenBlog.config.authenticate = ->(_) { OpenBlog::Actor.new(name: "Observer", scopes: []) }
    get :index
    assert_error 403, "scope_required", [ "read" ]
  end

  test "unknown user fields are refused while false and null survive input extraction" do
    OpenBlog.config.authenticate = ->(_) { OpenBlog::Actor.new(name: "Reader") }
    get :index, params: { extra: "no" }
    assert_error 422, "unknown_field", [ "extra" ]
    post :index, params: { value: false }, as: :json
    assert_equal false, response.parsed_body["value"]
  end

  test "native rate limiter shares actor quota and isolates another actor" do
    OpenBlog.config.authenticate = ->(_) { OpenBlog::Actor.new(name: "First") }
    2.times { get :index; assert_response :success }
    @controller = ApiBaseOtherProbeController.new
    @routes.draw { get "/other", to: "api_base_other_probe#index" }
    get :index
    assert_error 429, "rate_limited", []
    OpenBlog.config.authenticate = ->(_) { OpenBlog::Actor.new(name: "Second") }
    get :index
    assert_response :success
  end

  test "legacy limiter proxy only normalizes its own controller namespace" do
    store = ActiveSupport::Cache::MemoryStore.new
    proxy = OpenBlog::Api::V1::BaseController::SharedLimitStore.new(store, "open_blog/api/v1/posts")
    proxy.increment("rate-limit:open_blog/api/v1/posts:actor", 1, expires_in: 60)
    proxy.increment("rate-limit:sessions:actor", 1, expires_in: 60)
    assert_equal 1, store.read("rate-limit:open_blog/api:actor")
    assert_equal 1, store.read("rate-limit:sessions:actor")
    assert_nil store.read("rate-limit:open_blog/api/v1/posts:actor")
  end

  private

  def assert_error(status, code, details)
    assert_response status
    assert_equal [ "error" ], response.parsed_body.keys
    assert_equal code, response.parsed_body.dig("error", "code")
    assert_equal details, response.parsed_body.dig("error", "details")
    assert_equal %w[code details message], response.parsed_body["error"].keys.sort
    assert_includes response.headers["Cache-Control"], "no-store"
  end
end
