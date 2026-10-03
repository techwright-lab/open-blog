require_relative "test_helper"

class ApiAcceptanceTest < ActionDispatch::IntegrationTest
  setup do
    @settings = %i[authenticate api_rate_limit rate_limit_store require_approval before_publish].to_h { |key| [ key, OpenBlog.config.public_send(key) ] }
    OpenBlog.config.authenticate = nil
    OpenBlog.config.api_rate_limit = { to: 10000, within: 1.minute }
    OpenBlog.config.rate_limit_store = ActiveSupport::Cache::MemoryStore.new
    @post = OpenBlog::SaveDraft.call({ title: "River notes", body: "A quiet afternoon." }, actor: "Writer").post
  end

  teardown { @settings.each { |key, value| OpenBlog.config.public_send("#{key}=", value) } }

  test "all shipped methods reject missing revoked expired and insufficient credentials" do
    revoked, revoked_secret = OpenBlog::ApiToken.generate(name: "Revoked")
    revoked.update!(revoked_at: Time.current)
    _expired, expired_secret = OpenBlog::ApiToken.generate(name: "Expired", expires_at: 1.minute.ago)
    _limited, limited_secret = OpenBlog::ApiToken.generate(name: "No permissions", scopes: [])
    endpoints.each do |method, path, scope, params|
      [ nil, revoked_secret, expired_secret ].each do |secret|
        public_send(method, path, params: params, headers: credentials(secret), as: :json)
        assert_error 401, "unauthenticated", []
      end
      public_send(method, path, params: params, headers: credentials(limited_secret), as: :json)
      assert_error 403, "scope_required", [ scope ]
    end
    assert_equal "draft", @post.reload.status
    assert_empty @post.revisions
    assert_empty @post.connection_declarations
  end

  test "default quota refuses request 121 and leaves another token independent" do
    OpenBlog.config.api_rate_limit = OpenBlog::Configuration.new.api_rate_limit
    _first, first = OpenBlog::ApiToken.generate(name: "First reader", scopes: [ "read" ])
    _second, second = OpenBlog::ApiToken.generate(name: "Second reader", scopes: [ "read" ])
    travel_to Time.current.change(usec: 0) do
      120.times do
        get "/blog/api/v1/posts", headers: credentials(first)
        assert_response :ok
      end
      get "/blog/api/v1/posts/#{@post.id}/records", headers: credentials(first)
      assert_error 429, "rate_limited", []
      get "/blog/api/v1/posts/#{@post.id}/records", headers: credentials(second)
      assert_response :ok
    end
  end

  test "publication gate and slug refusals keep typed HTTP errors and rollback" do
    OpenBlog.config.authenticate = ->(_) { Struct.new(:name).new("Publisher") }
    OpenBlog.config.require_approval = true
    post "/blog/api/v1/posts", params: { title: "Gate notes", publish: true, provenance: "ai_assisted" }, as: :json
    assert_error 422, "approval_required", []
    OpenBlog.config.require_approval = false
    OpenBlog.config.before_publish = ->(_post, _context) { [ "A reviewer must confirm the route." ] }
    post "/blog/api/v1/posts", params: { title: "Gate notes", publish: true }, as: :json
    assert_error 422, "refused_by_host", [ "A reviewer must confirm the route." ]
    OpenBlog.config.before_publish = nil
    post "/blog/api/v1/posts", params: { title: "Gate notes", slug: "route/one" }, as: :json
    assert_error 422, "validation_failed", [ "slug" ]
    assert_equal 1, OpenBlog::Post.count
    assert_equal 0, OpenBlog::Publication.count
  end

  test "deferred endpoints and unsupported verbs are not routable" do
    paths = [ [ :get, "/posts/#{@post.id}/preview" ], [ :post, "/images" ], [ :get, "/pages" ],
      [ :get, "/posts/#{@post.id}/views" ], [ :get, "/views/top" ], [ :get, "/report" ],
      [ :get, "/standard" ], [ :put, "/posts/#{@post.id}" ] ]
    paths.each do |method, suffix|
      route = OpenBlog::Engine.routes.recognize_path("/api/v1#{suffix}", method: method)
      refute route[:controller].to_s.start_with?("open_blog/api/"), "Unexpected API route: #{method} #{suffix}"
    rescue ActionController::RoutingError
      assert true
    end
  end

  private

  def endpoints
    path = "/blog/api/v1/posts/#{@post.id}"
    [
      [ :get, "/blog/api/v1/posts", "read", {} ], [ :get, path, "read", {} ],
      [ :post, "/blog/api/v1/posts", "write", { title: "New note" } ],
      [ :post, "/blog/api/v1/posts", "publish", { title: "New note", publish: true } ],
      [ :patch, path, "write", { title: "Edited note" } ],
      [ :post, "#{path}/publish", "publish", {} ], [ :post, "#{path}/unpublish", "publish", {} ],
      [ :delete, path, "publish", {} ], [ :post, "#{path}/approvals", "publish", {} ],
      [ :post, "#{path}/connections", "publish", {} ], [ :get, "#{path}/records", "read", {} ],
      [ :get, "#{path}/findings", "read", {} ], [ :get, "/blog/api/v1/doctor", "read", {} ]
    ]
  end

  def credentials(secret)
    secret ? { "Authorization" => "Bearer #{secret}" } : {}
  end

  def assert_error(status, code, details)
    assert_response status
    assert_equal [ "error" ], response.parsed_body.keys
    assert_equal %w[code details message], response.parsed_body.fetch("error").keys.sort
    assert_equal code, response.parsed_body.dig("error", "code")
    assert_equal details, response.parsed_body.dig("error", "details")
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_nil response.headers["Set-Cookie"]
  end
end
