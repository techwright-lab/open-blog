require_relative "test_helper"

class ApiPublishingFlowTest < ActionDispatch::IntegrationTest
  setup do
    @settings = %i[authenticate api_rate_limit rate_limit_store].to_h { |key| [ key, OpenBlog.config.public_send(key) ] }
    OpenBlog.config.authenticate = nil
    OpenBlog.config.api_rate_limit = { to: 120, within: 1.minute }
    OpenBlog.config.rate_limit_store = ActiveSupport::Cache::MemoryStore.new
    @token, secret = OpenBlog::ApiToken.generate(name: "Trail editor")
    @headers = { "Authorization" => "Bearer #{secret}" }
  end

  teardown { @settings.each { |key, value| OpenBlog.config.public_send("#{key}=", value) } }

  test "a token drives the complete publication history and preserves it on removal" do
    post "/blog/api/v1/posts", params: { title: "An afternoon trail", body: "The route begins by the bridge.",
      description: "A short walk beside the river.", provenance: "human_written", external_id: "trail-log" }, headers: @headers, as: :json
    assert_api :created
    data = response.parsed_body
    id = data.dig("post", "id")
    path = "/blog/api/v1/posts/#{id}"
    assert_equal "draft", data.dig("post", "status")
    assert_empty OpenBlog::Post.find(id).revisions

    post "#{path}/publish", headers: @headers, as: :json
    assert_api :ok
    first_revision = response.parsed_body.dig("post", "public_revision_identifier")
    assert_equal "first", response.parsed_body.dig("records", "publication")

    patch path, params: { body: "The route begins by the bridge and ends at the meadow.", change: "substantive" }, headers: @headers, as: :json
    assert_api :ok
    revision = response.parsed_body.dig("post", "public_revision_identifier")
    refute_equal first_revision, revision
    assert_equal "substantive", response.parsed_body.dig("records", "publication")
    assert_equal false, response.parsed_body.dig("post", "approved")

    post "#{path}/approvals", params: { revision_identifier: revision, name: "Casey", facts_checked: true }, headers: @headers, as: :json
    assert_api :ok
    assert_equal true, response.parsed_body.dig("post", "approved")

    get "#{path}/records", headers: @headers
    assert_api :ok
    records = response.parsed_body
    assert_equal [ first_revision, revision ], records.fetch("revisions").pluck("identifier")
    assert_equal %w[first substantive], records.fetch("publications").pluck("entry_type")
    assert_equal [ "Trail editor", "Trail editor" ], records.fetch("revisions").pluck("actor")
    assert_equal revision, records.fetch("approvals").first.fetch("revision_identifier")
    assert_equal "Trail editor", records.fetch("approvals").first.fetch("recorded_by")

    post "#{path}/unpublish", headers: @headers, as: :json
    assert_api :ok
    assert_equal "draft", response.parsed_body.dig("post", "status")
    assert OpenBlog::Redirect.exists?(post_id: id, new_path: nil)
    delete path, headers: @headers
    assert_api :ok
    assert_equal "archived", response.parsed_body.dig("post", "status")
    get "#{path}/records", headers: @headers
    assert_api :ok
    assert_equal records, response.parsed_body
    assert @token.reload.last_used_at

    post "/blog/api/v1/posts", params: { title: "Unused trail", body: "A draft route." }, headers: @headers, as: :json
    assert_api :created
    draft_id = response.parsed_body.dig("post", "id")
    delete "/blog/api/v1/posts/#{draft_id}", headers: @headers
    assert_api :no_content
    assert_empty response.body
    refute OpenBlog::Post.exists?(draft_id)
  end

  private

  def assert_api(status)
    assert_response status
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_nil response.headers["Set-Cookie"]
  end
end
