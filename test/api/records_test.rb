require_relative "../test_helper"

class ApiRecordsTest < ActionDispatch::IntegrationTest
  setup do
    @authentication = OpenBlog.config.authenticate
    OpenBlog.config.authenticate = ->(_request) { Struct.new(:name).new("Archive editor") }
    @post = OpenBlog::Publish.call({ title: "Seed inventory", body: "## Beds\n\n### Rows", provenance: "human_written" }, actor: "Writer").post
  end

  teardown { OpenBlog.config.authenticate = @authentication }

  test "records expose explicit immutable shapes and preserve evidence" do
    revision = @post.public_revision
    @post.approvals.create!(revision: revision, kind: "declared", reviewer_name: "Reviewer", facts_checked: false,
      approved_at: Time.current, declared_on: Date.current, declared_by: "Publisher", recorded_by: "Importer")
    @post.approvals.create!(revision: revision, kind: "imported", reviewer_name: "Reviewer", facts_checked: true,
      approved_at: Time.current, confirmed_by: "Archivist", evidence: "Signed ledger", recorded_by: "Importer")
    @post.create_baseline!(adopted_revision: revision, adopted_at: Time.current, provenance: "human_written",
      declared_first_published_at: 2.days.ago, source_system: "archive", source_id: "seed-1", adopted_by: "Importer")
    get endpoint("records")
    assert_response :success
    assert_equal %w[approvals baseline connections publications revisions], response.parsed_body.keys.sort
    assert_equal %w[actor created_at identifier made_by_ai], response.parsed_body.fetch("revisions").first.keys.sort
    approvals = response.parsed_body.fetch("approvals")
    assert_equal %w[approved_at confirmed_by declared_by declared_on evidence facts_checked kind recorded_by reviewer_name revision_identifier], approvals.first.keys.sort
    assert_equal "Publisher", approvals.first["declared_by"]
    assert_equal "Signed ledger", approvals.last["evidence"]
    assert_equal %w[description entry_type note occurred_at released_by revision_identifier], response.parsed_body.fetch("publications").first.keys.sort
    baseline = response.parsed_body.fetch("baseline")
    assert_equal %w[adopted_at adopted_by adopted_revision_id declared_first_published_at first_published_at first_published_evidence last_modified_at last_modified_evidence post_id provenance provenance_evidence source_body_sha256 source_id source_system], baseline.keys.sort
    assert_nil baseline["first_published_at"]
    assert baseline["declared_first_published_at"]
    assert_no_store
  end

  test "absent baseline stays null and records resolve slugs" do
    get "/blog/api/v1/posts/#{@post.slug}/records"
    assert_response :success
    assert_nil response.parsed_body["baseline"]
    assert_equal [], response.parsed_body["connections"]
  end

  test "late approval writes only approval and returns a write result" do
    assert_no_difference [ "OpenBlog::Revision.count", "OpenBlog::Publication.count" ] do
      assert_difference "OpenBlog::Approval.count", 1 do
        post endpoint("approvals"), params: { revision_identifier: @post.public_revision.identifier, name: "Reviewer", facts_checked: false }, as: :json
      end
    end
    assert_response :success
    assert_equal({ "revision" => "same", "publication" => nil, "approval" => "sent" }, response.parsed_body["records"])
    assert_equal false, @post.approvals.last.facts_checked
    assert_equal "Archive editor", @post.approvals.last.recorded_by
    assert_no_store
  end

  test "approval refusals are typed and write nothing" do
    assert_no_difference "OpenBlog::Approval.count" do
      post endpoint("approvals"), params: { revision_identifier: "outdated", name: "Reviewer", facts_checked: true }, as: :json
      assert_error 409, "revision_mismatch", []
      post endpoint("approvals"), params: { revision_identifier: @post.public_revision.identifier, facts_checked: true }, as: :json
      assert_error 422, "approval_incomplete", []
      post endpoint("approvals"), params: { revision_identifier: @post.public_revision.identifier, name: "Reviewer", facts_checked: "true" }, as: :json
      assert_error 422, "approval_incomplete", []
    end
  end

  test "connection declarations append complete snapshots without altering content" do
    travel_to Time.zone.parse("2026-10-03 12:00:00") do
      assert_no_difference [ "OpenBlog::Revision.count", "OpenBlog::Publication.count" ] do
        post endpoint("connections"), params: { connections: [ { party: "Seed guild", relation: "Member" } ], third_party_paid: false, declared_by: "Publisher" }, as: :json
        assert_response :success
        assert_nil response.parsed_body.dig("records", "revision")
        post endpoint("connections"), params: { connections: [], third_party_paid: false, declared_by: "Publisher", declared_on: "2026-10-02" }, as: :json
        assert_response :success
      end
      rows = @post.connection_declarations.order(:id).to_a
      assert_equal 2, rows.size
      assert_equal Date.current, rows.first.declared_on
      assert_equal [], rows.last.connections
      assert_equal Date.new(2026, 10, 2), rows.last.declared_on
      assert_equal "Archive editor", rows.last.recorded_by
      get endpoint("records")
      assert_equal %w[connections declared_by declared_on post_id recorded_by third_party_paid], response.parsed_body.fetch("connections").first.keys.sort
    end
  end

  test "a declaration on an unaudited draft does not claim a revision record" do
    @post = OpenBlog::SaveDraft.call({ title: "Draft inventory" }, actor: "Editor").post
    post endpoint("connections"), params: { connections: [], third_party_paid: false, declared_by: "Publisher" }, as: :json
    assert_response :ok
    assert_equal({ "revision" => nil, "publication" => nil, "approval" => nil }, response.parsed_body.fetch("records"))
    assert_empty @post.revisions
  end

  test "malformed declarations and unsupported fields fail before writing" do
    valid = { connections: [], third_party_paid: false, declared_by: "Publisher" }
    assert_no_difference "OpenBlog::ConnectionDeclaration.count" do
      post endpoint("connections"), params: valid.merge(secret: "ignored?"), as: :json
      assert_error 422, "unknown_field", [ "secret" ]
      post endpoint("connections"), params: valid.merge(connections: [ { party: "Guild", relation: "Member", hidden: true } ]), as: :json
      assert_error 422, "unknown_field", [ "connections.hidden" ]
      [ { connections: nil }, { third_party_paid: "false" }, { declared_by: 123 }, { declared_on: "2026-02-30" } ].each do |invalid|
        post endpoint("connections"), params: valid.merge(invalid), as: :json
        assert_error 422, "validation_failed", invalid.keys.map(&:to_s)
      end
    end
  end

  test "findings read stored content without any record writes" do
    @post = OpenBlog::SaveDraft.call({ title: "Seed inventory", slug: "second-inventory", body: "## Beds\n\n#### Skipped\n\n![ ](https://example.test/missing.png)" }, actor: "Writer").post
    counts = [ "OpenBlog::Revision.count", "OpenBlog::Publication.count", "OpenBlog::Approval.count", "OpenBlog::ConnectionDeclaration.count" ]
    writes = []
    subscriber = ->(_name, _start, _finish, _id, payload) { writes << payload[:sql] if payload[:sql].match?(/\A\s*(INSERT|UPDATE|DELETE)\b/i) }
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      assert_no_difference counts do
        get endpoint("findings")
      end
    end
    assert_empty writes
    assert_response :success
    assert_equal [ "findings" ], response.parsed_body.keys
    codes = response.parsed_body.fetch("findings").map { |entry| entry.fetch("code") }
    %w[description_absent heading_level_skipped title_duplicate image_alt_absent].each { |code| assert_includes codes, code }
    response.parsed_body["findings"].each { |entry| assert_equal %w[code location message rule], entry.keys.sort }
    assert_no_store
  end

  test "doctor returns only the documented check envelope" do
    get "/blog/api/v1/doctor"
    assert_response :success
    assert_equal [ "checks" ], response.parsed_body.keys
    assert_equal 13, response.parsed_body["checks"].size
    response.parsed_body["checks"].each do |entry|
      assert_equal %w[message name status], entry.keys.sort
      assert_includes %w[ok warning error], entry["status"]
    end
    assert_no_store
  end

  test "each records action requires its scope and authentication" do
    [ [ :get, "records", :read ], [ :get, "findings", :read ], [ :post, "approvals", :publish ], [ :post, "connections", :publish ], [ :get, nil, :read ] ].each do |method, action, scope|
      path = action ? endpoint(action) : "/blog/api/v1/doctor"
      OpenBlog.config.authenticate = ->(_request) { nil }
      public_send(method, path, as: :json)
      assert_error 401, "unauthenticated", []
      OpenBlog.config.authenticate = ->(_request) { Struct.new(:name, :scopes).new("Reader", []) }
      public_send(method, path, as: :json)
      assert_error 403, "scope_required", [ scope.to_s ]
    end
  end

  test "revoked and expired tokens fail at every record endpoint" do
    OpenBlog.config.authenticate = nil
    revoked, revoked_secret = OpenBlog::ApiToken.generate(name: "Revoked reader")
    revoked.update!(revoked_at: Time.current)
    expired, expired_secret = OpenBlog::ApiToken.generate(name: "Expired reader", expires_at: 1.minute.ago)
    [ revoked_secret, expired_secret ].each do |secret|
      [ [ :get, "records" ], [ :get, "findings" ], [ :post, "approvals" ], [ :post, "connections" ], [ :get, nil ] ].each do |method, action|
        public_send(method, action ? endpoint(action) : "/blog/api/v1/doctor", headers: { "Authorization" => "Bearer #{secret}" }, as: :json)
        assert_error 401, "unauthenticated", []
      end
    end
    assert_nil revoked.reload.last_used_at
    assert_nil expired.reload.last_used_at
  end

  test "read endpoints refuse unsupported query fields and missing posts" do
    %w[records findings].each do |action|
      get endpoint(action), params: { format: "secret" }
      assert_error 422, "unknown_field", [ "format" ]
      get "/blog/api/v1/posts/missing-post/#{action}"
      assert_error 404, "not_found", []
    end
    get "/blog/api/v1/doctor", params: { controller: "other" }
    assert_error 422, "unknown_field", [ "controller" ]
  end

  private

  def endpoint(action)
    "/blog/api/v1/posts/#{@post.id}/#{action}"
  end

  def assert_no_store
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  def assert_error(status, code, details)
    assert_response status
    assert_equal code, response.parsed_body.dig("error", "code")
    assert_equal details, response.parsed_body.dig("error", "details")
    assert_no_store
  end
end
