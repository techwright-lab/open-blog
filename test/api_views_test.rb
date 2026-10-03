require_relative "test_helper"

class ApiViewsTest < ActionDispatch::IntegrationTest
  setup do
    @hook = OpenBlog.config.authenticate
    @scopes = [ "read" ]
    OpenBlog.config.authenticate = ->(_) { OpenBlog::Actor.new(name: "Statistics reader", scopes: @scopes) }
    @post = OpenBlog::SaveDraft.call({ title: "Quiet trail" }, actor: "Editor").post
    travel_to Time.utc(2026, 10, 6, 12)
    OpenBlog::PageView.create!(post: @post, day: Date.current, views: 8)
    OpenBlog::PageView.create!(post: @post, day: Date.current - 10, views: 2)
  end
  teardown do
    OpenBlog.config.authenticate = @hook
    travel_back
  end

  test "daily and top objects expose only totals with default and selected ranges" do
    get "/blog/api/v1/posts/#{@post.slug}/views"
    assert_response :ok
    assert_equal %w[days from post_id to total], response.parsed_body.keys.sort
    assert_equal "2026-09-07", response.parsed_body["from"]
    assert_equal 10, response.parsed_body["total"]
    assert_equal [ { "day" => "2026-09-26", "views" => 2 }, { "day" => "2026-10-06", "views" => 8 } ], response.parsed_body["days"]
    get "/blog/api/v1/posts/#{@post.id}/views", params: { from: "2026-10-01", to: "2026-10-06" }
    assert_equal 8, response.parsed_body["total"]
    get "/blog/api/v1/views/top", params: { days: 7, limit: 3 }
    assert_response :ok
    expected = response.parsed_body
    assert_equal %w[days posts], expected.keys.sort
    assert_equal %w[id slug title url views], expected["posts"].first.keys.sort
    assert_equal 8, expected["posts"].first["views"]
    tool = OpenBlog::Mcp.definitions.find { |definition| definition.name == "blog_get_page_views" }
    assert_equal expected, tool.call({ days: 7, limit: 3 }, actor: OpenBlog::Actor.new(name: "Reader", scopes: [ "read" ]))
    [ { from: "2026-10-01" }, { id: @post.id, days: 7 }, { id: @post.id, limit: 3 } ].each do |arguments|
      assert_equal "validation_failed", tool.call(arguments, actor: OpenBlog::Actor.new(name: "Reader")).dig("error", "code")
    end
  end

  test "all view endpoints reject missing authentication missing read scope and invalid inputs" do
    paths = [ "/blog/api/v1/posts/#{@post.id}/views", "/blog/api/v1/views/top" ]
    OpenBlog.config.authenticate = nil
    paths.each { |path| get path; assert_response :unauthorized }
    OpenBlog.config.authenticate = ->(_) { OpenBlog::Actor.new(name: "Writer", scopes: [ "write" ]) }
    paths.each { |path| get path; assert_response :forbidden; assert_equal "scope_required", response.parsed_body.dig("error", "code") }
    OpenBlog.config.authenticate = ->(_) { OpenBlog::Actor.new(name: "Reader", scopes: [ "read" ]) }
    [ { days: 0 }, { days: 36501 }, { limit: 101 }, { limit: "1x" }, { days: nil } ].each do |input|
      get paths.last, params: input, as: :json
      assert_response :unprocessable_entity
      assert_equal "validation_failed", response.parsed_body.dig("error", "code")
    end
    [ { from: "2026-02-30" }, { to: "2026-10-06junk" }, { from: "2027-01-01" } ].each do |input|
      get paths.first, params: input
      assert_response :unprocessable_entity
    end
    get paths.first, params: { days: 3 }
    assert_equal "unknown_field", response.parsed_body.dig("error", "code")
    get "/blog/api/v1/posts/missing-statistics/views"
    assert_response :not_found
    assert_includes response.headers["Cache-Control"], "no-store"
    tool = OpenBlog::Mcp.definitions.find { |definition| definition.name == "blog_get_page_views" }
    assert_equal "scope_required", tool.call({}, actor: OpenBlog::Actor.new(name: "Writer", scopes: [ "write" ])).dig("error", "code")
  end
end
