require_relative "test_helper"

class ApiPagesTest < ActionDispatch::IntegrationTest
  setup do
    @hook = OpenBlog.config.authenticate
    @scopes = %w[read write publish]
    OpenBlog.config.authenticate = ->(_) { OpenBlog::Actor.new(name: "Policy editor", scopes: @scopes) }
  end
  teardown { OpenBlog.config.authenticate = @hook }

  test "page upsert returns explicit fields and defaults approval date" do
    travel_to Time.zone.parse("2026-10-05 12:00:00") do
      put "/blog/api/v1/pages/responsible_party", params: { title: "Our publisher", body: "Contact our editor.", approved_by: "Casey" }, as: :json
      assert_response :created
      assert_equal %w[approved_by approved_on body kind slug status title updated_at url], response.parsed_body.keys.sort
      assert_equal "2026-10-05", response.parsed_body["approved_on"]
      assert_equal "draft", response.parsed_body["status"]
      assert_equal "https://example.test/blog/policies/responsible-party", response.parsed_body["url"]
      put "/blog/api/v1/pages/responsible_party", params: { body: "Email the editor.", status: "published" }, as: :json
      assert_response :ok
      assert_equal "Our publisher", response.parsed_body["title"]
      get "/blog/api/v1/pages"
      assert_response :ok
      assert_equal %w[page pages per_page total], response.parsed_body.keys.sort
      assert_equal 1, response.parsed_body["total"]
      get "/blog/api/v1/pages/responsible_party"
      assert_response :ok
      assert_equal "published", response.parsed_body["status"]
    end
  end

  test "missing pages and unsupported inputs are typed and never cached" do
    get "/blog/api/v1/pages/ai_use"
    assert_error 404, "not_found", []
    [ { publish: true }, { kind: "editorial" } ].each do |input|
      put "/blog/api/v1/pages/ai_use", params: input, as: :json
      assert_error 422, "unknown_field", input.keys.map(&:to_s)
    end
    [ { approved_on: "2026-02-30" }, { approved_on: "2026-10-01junk" }, { title: 1 }, { body: nil }, { status: "archived" } ].each do |input|
      put "/blog/api/v1/pages/ai_use", params: { title: "AI use", body: "Our process." }.merge(input), as: :json
      assert_error 422, "validation_failed", input.keys.map(&:to_s)
    end
    assert_equal 0, OpenBlog::Page.count
  end

  test "writes require write and published current or requested state also requires publish" do
    @scopes = [ "write" ]
    put "/blog/api/v1/pages/editorial", params: { title: "Editorial", body: "Our process." }, as: :json
    assert_response :created
    put "/blog/api/v1/pages/editorial", params: { status: "published" }, as: :json
    assert_error 403, "scope_required", [ "publish" ]
    @scopes = [ "publish" ]
    put "/blog/api/v1/pages/editorial", params: { status: "published" }, as: :json
    assert_error 403, "scope_required", [ "write" ]
    @scopes = %w[write publish]
    put "/blog/api/v1/pages/editorial", params: { status: "published" }, as: :json
    assert_response :ok
    @scopes = [ "write" ]
    [ { body: "Changed" }, { status: "draft" } ].each do |input|
      put "/blog/api/v1/pages/editorial", params: input, as: :json
      assert_error 403, "scope_required", [ "publish" ]
    end
    assert_equal "Our process.", OpenBlog::Page.find_by!(kind: "editorial").body_markdown
  end

  test "page endpoints enforce bearer authentication and read scope" do
    OpenBlog.config.authenticate = nil
    expired, secret = OpenBlog::ApiToken.generate(name: "Expired", expires_at: 1.minute.ago)
    revoked, revoked_secret = OpenBlog::ApiToken.generate(name: "Revoked")
    revoked.update!(revoked_at: Time.current)
    [ [ :get, "/pages" ], [ :get, "/pages/editorial" ], [ :put, "/pages/editorial" ] ].each do |method, path|
      [ nil, secret, revoked_secret ].each do |token|
        public_send(method, "/blog/api/v1#{path}", headers: token ? { "Authorization" => "Bearer #{token}" } : {}, as: :json)
        assert_error 401, "unauthenticated", []
      end
    end
    assert_nil expired.reload.last_used_at
    OpenBlog.config.authenticate = ->(_) { OpenBlog::Actor.new(name: "No permissions", scopes: []) }
    get "/blog/api/v1/pages"
    assert_error 403, "scope_required", [ "read" ]
  end

  test "page tools keep dynamic publication scopes and expose the canonical stored page URL" do
    actor = OpenBlog::Actor.new(name: "Draft editor", scopes: [ "write" ])
    tool = OpenBlog::Mcp.definitions.find { |definition| definition.name == "blog_save_site_page" }
    result = tool.call({ kind: "corrections", title: "Corrections", body: "Tell our editor." }, actor: actor)
    assert_equal "draft", result["status"]
    result = tool.call({ kind: "corrections", status: "published" }, actor: actor)
    assert_equal "scope_required", result.dig("error", "code")
    assert_equal [ "publish" ], result.dig("error", "details")
    previous = OpenBlog.config.policy_urls.dup
    OpenBlog.config.policy_urls[:corrections] = "https://publisher.example/corrections"
    get "/blog/api/v1/pages/corrections"
    assert_equal "https://example.test/blog/policies/corrections", response.parsed_body["url"]
  ensure
    OpenBlog.config.policy_urls = previous if previous
  end

  test "approval dates are never invented for missing names and explicit dates survive name changes" do
    [ nil, "" ].each do |name|
      put "/blog/api/v1/pages/ai_use", params: { title: "AI use", body: "Our approach.", approved_by: name }, as: :json
      assert_response :success
      assert_nil response.parsed_body["approved_on"]
    end
    put "/blog/api/v1/pages/ai_use", params: { approved_by: "New reviewer", approved_on: "2025-04-03" }, as: :json
    assert_response :ok
    assert_equal "2025-04-03", response.parsed_body["approved_on"]
    put "/blog/api/v1/pages/ai_use", params: { title: "Updated AI use" }, as: :json
    assert_response :ok
    assert_equal "2025-04-03", response.parsed_body["approved_on"]
    put "/blog/api/v1/pages/ai_use", params: { approved_by: nil, approved_on: nil }, as: :json
    assert_response :ok
    assert_nil response.parsed_body["approved_by"]
    assert_nil response.parsed_body["approved_on"]
  end

  private

  def assert_error(status, code, details)
    assert_response status
    assert_equal code, response.parsed_body.dig("error", "code")
    assert_equal details, response.parsed_body.dig("error", "details")
    assert_equal "no-store", response.headers["Cache-Control"]
  end
end
