require_relative "test_helper"
require "minitest/mock"

class McpTransportTest < ActionDispatch::IntegrationTest
  setup do
    @settings = %i[authenticate api_rate_limit rate_limit_store].to_h { |key| [ key, OpenBlog.config.public_send(key) ] }
    @enabled = OpenBlog.config.mcp.enabled
    OpenBlog.config.mcp.enabled = true
    OpenBlog.config.authenticate = nil
    OpenBlog.config.api_rate_limit = { to: 120, within: 1.minute }
    OpenBlog.config.rate_limit_store = ActiveSupport::Cache::MemoryStore.new
    @token, secret = OpenBlog::ApiToken.generate(name: "Tool editor")
    @headers = { "Authorization" => "Bearer #{secret}" }
  end

  teardown do
    @settings.each { |key, value| OpenBlog.config.public_send("#{key}=", value) }
    OpenBlog.config.mcp.enabled = @enabled
  end

  test "tools are served on a real host and tool responses preserve structured API objects" do
    definition = echo_definition
    OpenBlog::Mcp.stub(:definitions, [ definition ]) do
      host! "journal.example.test"
      rpc("tools/list")
      assert_response :success
      assert_equal "blog_echo", response.parsed_body.dig("result", "tools", 0, "name")
      rpc("tools/call", { name: "blog_echo", arguments: { value: "sample" } })
      result = response.parsed_body.fetch("result")
      assert_equal false, result.fetch("isError")
      assert_equal({ "value" => "sample", "actor" => "Tool editor" }, result["structuredContent"])
      assert_equal result["structuredContent"], JSON.parse(result.fetch("content").first.fetch("text"))
      assert_equal "no-store", response.headers["Cache-Control"]
      assert_nil response.headers["Set-Cookie"]
    end
  end

  test "missing credentials and insufficient tool scopes are refused" do
    post "/blog/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }, as: :json
    assert_response :unauthorized
    assert_equal "unauthenticated", response.parsed_body.dig("error", "code")
    OpenBlog::Mcp.stub(:definitions, [ echo_definition(scope: :publish) ]) do
      token, secret = OpenBlog::ApiToken.generate(name: "Reader", scopes: [ "read" ])
      @headers["Authorization"] = "Bearer #{secret}"
      rpc("tools/call", { name: "blog_echo", arguments: { value: "sample" } })
      assert_response :success
      assert_equal true, response.parsed_body.dig("result", "isError")
      assert_equal "scope_required", response.parsed_body.dig("result", "structuredContent", "error", "code")
      assert token.reload.last_used_at
    end
  end

  test "origin checks distinguish scheme hostname and effective port" do
    OpenBlog::Mcp.stub(:definitions, []) do
      host! "journal.example.test"
      [ "http://journal.example.test", OpenBlog.config.public_base_url ].compact.each do |origin|
        @headers["Origin"] = origin
        rpc("tools/list")
        assert_response :success
      end
      %w[null https://journal.example.test http://journal.example.test:8080 http://other.example.test http://user@journal.example.test].each do |origin|
        @headers["Origin"] = origin
        rpc("tools/list")
        assert_response :forbidden
        assert_equal "no-store", response.headers["Cache-Control"]
      end
    end
  end

  test "disabled transport missing methods and notifications have protocol statuses" do
    OpenBlog::Mcp.stub(:definitions, []) do
      [ :get, :delete ].each do |method|
        public_send(method, "/blog/mcp", headers: @headers)
        assert_response :method_not_allowed
        assert_equal "POST", response.headers["Allow"]
        assert_equal "no-store", response.headers["Cache-Control"]
      end
      post "/blog/mcp", params: { jsonrpc: "2.0", method: "notifications/initialized" }, headers: @headers, as: :json
      assert_response :accepted
      assert_empty response.body
      OpenBlog.config.mcp.enabled = false
      rpc("tools/list")
      assert_response :not_found
      assert_equal "no-store", response.headers["Cache-Control"]
    end
  end

  test "malformed JSON remains a JSON RPC error and each request consumes one quota" do
    OpenBlog::Mcp.stub(:definitions, [ echo_definition ]) do
      post "/blog/mcp", params: "{invalid", headers: @headers.merge("Content-Type" => "application/json")
      assert_response :success
      assert_equal(-32700, response.parsed_body.dig("error", "code"))
      OpenBlog.config.api_rate_limit = { to: 2, within: 1.minute }
      rpc("tools/call", { name: "blog_echo", arguments: { value: "sample" } })
      assert_response :success
      rpc("tools/list")
      assert_response :too_many_requests
      assert_equal "rate_limited", response.parsed_body.dig("error", "code")
    end
  end

  test "real tool dispatch shares the API pipeline and does not double charge requests" do
    OpenBlog.config.api_rate_limit = { to: 2, within: 1.minute }
    rpc("tools/call", { name: "blog_save_draft", arguments: { title: "Nest observations", body: "A nest beside the window." } })
    assert_response :success
    result = response.parsed_body.fetch("result")
    assert_equal false, result["isError"], result.inspect
    id = result.dig("structuredContent", "post", "id")
    rpc("tools/call", { name: "blog_get_post", arguments: { id: id } })
    assert_response :success
    assert_equal "Nest observations", response.parsed_body.dig("result", "structuredContent", "title")
    rpc("tools/list")
    assert_response :too_many_requests
  end

  test "HTTP input cannot impersonate an internally bound actor" do
    post "/blog/api/v1/posts", params: { title: "Forged", body: "No access", internal_actor: { name: "Editor", scopes: [ "write" ] } },
      headers: { "Open-Blog-Internal-Actor" => "Editor" }, as: :json
    assert_response :unauthorized
    assert_no_difference "OpenBlog::Post.count" do
      post "/blog/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "blog_save_draft", arguments: { title: "Forged", body: "No access" }, actor: { scopes: [ "write" ] } } }, as: :json
      assert_response :unauthorized
    end
  end

  private

  def rpc(method, params = {})
    post "/blog/mcp", params: { jsonrpc: "2.0", id: 1, method: method, params: params }, headers: @headers, as: :json
  end

  def echo_definition(scope: :read)
    OpenBlog::Mcp::Definition.new(name: "blog_echo", title: "Echo", description: "Returns a supplied value.", scope: scope,
      annotations: { read_only_hint: true }, input_schema: { type: "object", properties: { value: { type: "string" } }, required: [ "value" ], additionalProperties: false },
      handler: ->(arguments, actor:, base_url:) { { value: arguments[:value], actor: actor.name } })
  end
end
