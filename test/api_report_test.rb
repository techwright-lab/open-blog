require_relative "test_helper"
require "minitest/mock"

class ApiReportTest < ActionDispatch::IntegrationTest
  setup do
    @settings = %i[authenticate public_base_url].to_h { |key| [ key, OpenBlog.config.public_send(key) ] }
    OpenBlog.config.public_base_url = nil
    OpenBlog.config.authenticate = ->(_) { OpenBlog::Actor.new(name: "Report reader", scopes: [ "read" ]) }
  end
  teardown { @settings.each { |key, value| OpenBlog.config.public_send("#{key}=", value) } }

  test "reports support JSON text and MCP with the same scoped result" do
    travel_to Time.utc(2026, 10, 7, 12) do
      get "/blog/api/v1/report", params: { scope: "site" }
      assert_response :ok
      expected = response.parsed_body
      assert_equal "no-store", response.headers["Cache-Control"]
      tool = OpenBlog::Mcp.definitions.find { |entry| entry.name == "blog_get_surface_report" }
      assert_equal expected, tool.call({ scope: "site" }, actor: OpenBlog::Actor.new(name: "Reader", scopes: [ "read" ]))
      get "/blog/api/v1/report", params: { format: "text" }
      assert_response :ok
      assert_equal "text/plain", response.media_type
      assert_includes response.body, expected["sentence"]
      get "/blog/api/v1/report", headers: { "Accept" => "text/plain" }
      assert_equal "text/plain", response.media_type
    end
  end

  test "report authentication validation and unpublished selection are enforced" do
    OpenBlog.config.authenticate = nil
    get "/blog/api/v1/report"
    assert_response :unauthorized
    OpenBlog.config.authenticate = ->(_) { OpenBlog::Actor.new(name: "Writer", scopes: [ "write" ]) }
    get "/blog/api/v1/report"
    assert_response :forbidden
    OpenBlog.config.authenticate = @settings[:authenticate] || ->(_) { OpenBlog::Actor.new(name: "Reader", scopes: [ "read" ]) }
    [ { reach: "maybe" }, { scope: "unknown" }, { page: "-1" }, { url: "http://localhost" }, { format: "xml" } ].each do |input|
      get "/blog/api/v1/report", params: input
      assert_response :unprocessable_entity
    end
    get "/blog/api/v1/report", params: { scope: "post", post: "missing" }
    assert_response :not_found
  end
end
