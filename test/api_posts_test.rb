require_relative "test_helper"

class ApiPostsTest < ActionDispatch::IntegrationTest
  HookActor = Struct.new(:name, :scopes, keyword_init: true)
  FULL_KEYS = %w[id slug url status title description search_title search_description body_format body author category tags series featured canonical_url cover_image cover_alt social_image faq provenance provenance_evidence external_id published_at modified_at publish_at revision_identifier public_revision_identifier approved label preview_url reading_time_minutes word_count created_at updated_at].sort.freeze
  CARD_KEYS = %w[id slug url status title description author category tags published_at modified_at revision_identifier label].sort.freeze

  setup do
    @authentication = OpenBlog.config.authenticate
    @body_formats = OpenBlog.config.body_formats
    OpenBlog.config.body_formats = %i[markdown rich_text]
    @limit = OpenBlog.config.api_rate_limit
    @scopes = %w[read write publish]
    OpenBlog.config.authenticate = ->(_) { HookActor.new(name: "API Editor", scopes: @scopes) }
    OpenBlog.config.api_rate_limit = { to: 10000, within: 1.minute }
  end

  teardown do
    OpenBlog.config.body_formats = @body_formats
    OpenBlog.config.authenticate = @authentication
    OpenBlog.config.api_rate_limit = @limit
  end

  test "post writes and reads expose exact objects and route identity" do
    post "/blog/api/v1/posts", params: content.merge(external_id: "seed-notes", faq: [ { question: "When?", answer: "Spring.\r\nAfter frost." } ]), as: :json
    assert_response :created
    data = response.parsed_body
    assert_equal %w[created findings label post records], data.keys.sort
    assert_equal FULL_KEYS, data.fetch("post").keys.sort
    assert_equal %w[approval publication revision], data.fetch("records").keys.sort
    assert_nil data.dig("records", "revision")
    id = data.dig("post", "id")
    slug = data.dig("post", "slug")
    assert_match %r{/blog/preview/}, data.dig("post", "preview_url")
    assert_equal "Spring.\r\nAfter frost.", data.dig("post", "faq", 0, "answer")
    [ id, slug ].each do |identity|
      get "/blog/api/v1/posts/#{identity}"
      assert_response :success
      assert_equal FULL_KEYS, response.parsed_body.keys.sort
      assert_equal id, response.parsed_body.fetch("id")
    end
    post "/blog/api/v1/posts", params: content.merge(external_id: "seed-notes"), as: :json
    assert_response :ok
    assert_equal false, response.parsed_body.fetch("created")
    patch "/blog/api/v1/posts/#{id}", params: { description: "A practical guide" }, as: :json
    assert_response :ok
    assert_equal "A practical guide", OpenBlog::Post.find(id).description
  end

  test "list filters all states including draft FAQ text with independent totals" do
    first = OpenBlog::SaveDraft.call(content.merge(category: "Garden", tags: [ "Seeds" ], series: "Seasons", series_position: 1,
      faq: [ { question: "How many?", answer: "Exactly seventy seeds." } ]), actor: "Editor").post
    second = OpenBlog::Publish.call(content.merge(title: "Other note"), actor: "Editor").post
    get "/blog/api/v1/posts", params: { per_page: 1 }
    assert_response :ok
    assert_equal %w[page per_page posts total], response.parsed_body.keys.sort
    assert_equal 2, response.parsed_body["total"]
    assert_equal 1, response.parsed_body["posts"].size
    assert_equal CARD_KEYS, response.parsed_body["posts"].first.keys.sort
    { status: "draft", category: "garden", tag: "seeds", author: first.author.slug, series: "seasons", q: "SEVENTY" }.each do |filter, value|
      get "/blog/api/v1/posts", params: { filter => value, status: "draft" }
      assert_response :ok
      assert_equal [ first.id ], response.parsed_body["posts"].map { |row| row["id"] }, filter.to_s
    end
    get "/blog/api/v1/posts", params: { per_page: 500, status: "published" }
    assert_equal 100, response.parsed_body["per_page"]
    assert_equal [ second.id ], response.parsed_body["posts"].map { |row| row["id"] }
    get "/blog/api/v1/posts", params: { q: "%" }
    assert_empty response.parsed_body["posts"]
    [ { page: "0" }, { page: "1.5" }, { per_page: "wat" }, { status: "missing" }, { q: [ "x" ] } ].each do |query|
      get "/blog/api/v1/posts", params: query
      assert_response :unprocessable_entity
      assert_equal "validation_failed", response.parsed_body.dig("error", "code")
    end
  end

  test "publication amendment lifecycle and truthful approvals" do
    post "/blog/api/v1/posts", params: content.merge(publish: true, approval: { name: "Avery", facts_checked: true }), as: :json
    assert_response :created
    id = response.parsed_body.dig("post", "id")
    assert_equal true, response.parsed_body.dig("post", "approved")
    post "/blog/api/v1/posts", params: content.merge(slug: "seed-starting"), as: :json
    assert_error 409, "post_is_public"
    patch "/blog/api/v1/posts/#{id}", params: { body: "Changed content." }, as: :json
    assert_error 422, "change_type_required"
    patch "/blog/api/v1/posts/#{id}", params: { body: "Changed content.", change: "correction" }, as: :json
    assert_error 422, "correction_note_required"
    patch "/blog/api/v1/posts/#{id}", params: { body: "Changed content.", change: "substantive" }, as: :json
    assert_response :ok
    assert_equal false, response.parsed_body.dig("post", "approved")
    post "/blog/api/v1/posts/#{id}/unpublish", as: :json
    assert_response :ok
    assert_equal "draft", response.parsed_body.dig("post", "status")
    assert OpenBlog::Redirect.exists?(old_path: "/blog/seed-starting", new_path: nil)
    post "/blog/api/v1/posts/#{id}/publish", params: {}, as: :json
    assert_response :ok
    delete "/blog/api/v1/posts/#{id}", as: :json
    assert_response :ok
    assert_equal "archived", response.parsed_body.dig("post", "status")
    draft = OpenBlog::SaveDraft.call(content.merge(title: "Disposable"), actor: "Editor").post
    delete "/blog/api/v1/posts/#{draft.id}", as: :json
    assert_response :no_content
    refute OpenBlog::Post.exists?(draft.id)
  end

  test "write scope cannot edit scheduled or public records and patch keeps schedules" do
    draft = OpenBlog::SaveDraft.call(content, actor: "Editor").post
    @scopes = %w[write]
    patch "/blog/api/v1/posts/#{draft.id}", params: { title: "New title" }, as: :json
    assert_response :ok
    @scopes = %w[publish]
    due = 2.days.from_now.change(usec: 0)
    post "/blog/api/v1/posts/#{draft.id}/publish", params: { publish_at: due.iso8601 }, as: :json
    assert_response :accepted
    patch "/blog/api/v1/posts/#{draft.id}", params: { description: "Scheduled note" }, as: :json
    assert_response :ok
    assert_equal "scheduled", draft.reload.status
    assert_equal due, draft.publish_at
    @scopes = %w[write]
    patch "/blog/api/v1/posts/#{draft.id}", params: { body: "Forbidden" }, as: :json
    assert_error 403, "scope_required", [ "publish" ]
    post "/blog/api/v1/posts", params: { slug: draft.slug, body: "Forbidden" }, as: :json
    assert_error 403, "scope_required", [ "publish" ]
    assert_equal "Start with good seeds.", draft.reload.body_markdown
  end

  test "unknown inputs and nested keys are refused without mutation" do
    [ "status", "published_at", "categories", "id", "controller" ].each do |field|
      post "/blog/api/v1/posts", params: content.merge(field => "ignored?"), as: :json
      assert_error 422, "unknown_field", [ field ]
    end
    { author: { name: "Avery", secret: true }, approval: { name: "Avery", facts_checked: true, secret: true },
      faq: [ { question: "When?", answer: "Now", secret: true } ], cover_image: { image_id: 1, secret: true },
      connections: { connections: [], third_party_paid: false, declared_by: "Avery", secret: true } }.each do |field, value|
      post "/blog/api/v1/posts", params: content.merge(field => value), as: :json
      assert_error 422, "unknown_field", [ "#{field}.secret" ]
    end
    post "/blog/api/v1/posts", params: content.merge(connections: { connections: [ { party: "Garden club", relation: "Member", secret: true } ], third_party_paid: false, declared_by: "Avery" }), as: :json
    assert_error 422, "unknown_field", [ "connections.connections.secret" ]
    assert_equal 0, OpenBlog::Post.count
    post "/blog/api/v1/posts", params: content.merge(publish: "true"), as: :json
    assert_error 422, "validation_failed", [ "publish" ]
  end

  test "identity refusals and replacement lists leave stored state intact" do
    first = OpenBlog::SaveDraft.call(content.merge(external_id: "one", tags: [ "Seed", "Soil" ],
      faq: [ { question: "Old?", answer: "Old." } ]), actor: "Editor").post
    second = OpenBlog::SaveDraft.call(content.merge(title: "Another", external_id: "two"), actor: "Editor").post
    post "/blog/api/v1/posts", params: { external_id: "one", slug: second.slug }, as: :json
    assert_error 409, "identity_conflict"
    post "/blog/api/v1/posts", params: content.merge(slug: "api"), as: :json
    assert_error 409, "slug_reserved"
    patch "/blog/api/v1/posts/#{first.id}", params: { faq: [], tags: [ "Water" ] }, as: :json
    assert_response :ok
    assert_empty first.reload.faqs
    assert_equal [ "Water" ], first.tags.pluck(:name)
    post "/blog/api/v1/posts", params: content.merge(body_format: "unsupported"), as: :json
    assert_error 422, "body_format_not_permitted"
    get "/blog/api/v1/posts/does-not-exist"
    assert_error 404, "not_found"
  end

  test "full serializer uses stored rich text original media and explicit nested fields" do
    image = OpenBlog::Image.create!(sha256: "b" * 64, filename: "garden.png", content_type: "image/png", byte_size: 24, width: 8, height: 4)
    saved = OpenBlog::SaveDraft.call(content.merge(body_format: "rich_text", body: "<p>A <strong>small</strong> garden.</p>",
      category: "Gardening", series: "Notes", series_position: 2, cover_image: { image_id: image.id }, social_image: { image_id: image.id }), actor: "Editor")
    assert saved.success?, saved.error&.message
    get "/blog/api/v1/posts/#{saved.post.id}"
    assert_response :ok
    data = response.parsed_body
    assert_equal saved.post.body_for_payload, data["body"]
    assert_equal %w[id name slug type url], data["author"].keys.sort
    assert_equal %w[id name slug], data["category"].keys.sort
    assert_equal %w[id name position slug], data["series"].keys.sort
    assert_equal 2, data.dig("series", "position")
    assert_equal %w[byte_size content_type filename height image_id sha256 url width], data["cover_image"].keys.sort
    assert_equal image.path, data.dig("cover_image", "url")
    assert_equal image.id, data.dig("social_image", "image_id")
    assert_equal false, data["approved"]
  end

  test "removal accepts another post slug as a redirect destination" do
    source = OpenBlog::Publish.call(content, actor: "Editor").post
    target = OpenBlog::Publish.call(content.merge(title: "Successor"), actor: "Editor").post
    delete "/blog/api/v1/posts/#{source.id}", params: { redirect_to: target.slug }, as: :json
    assert_response :ok
    assert_equal target.path, OpenBlog::Redirect.find_by!(old_path: source.path).new_path
  end

  test "post writes append connection declarations with a default date and replace visible connections" do
    post "/blog/api/v1/posts", params: content.merge(connections: { connections: [ { party: "Garden club", relation: "Member" } ], third_party_paid: false, declared_by: "Avery" }), as: :json
    assert_response :created
    record = OpenBlog::Post.find(response.parsed_body.dig("post", "id"))
    first = record.connection_declarations.first!
    assert_equal Date.current, first.declared_on
    assert_equal "API Editor", first.recorded_by
    patch "/blog/api/v1/posts/#{record.id}", params: { connections: { connections: [], third_party_paid: false, declared_by: "Avery" } }, as: :json
    assert_response :ok
    assert_equal 2, record.connection_declarations.count
    assert_empty record.connection_declarations.order(:id).last.connections
    assert_equal [ { "party" => "Garden club", "relation" => "Member" } ], first.reload.connections
  end

  test "API authors require a name or an object even when an integer identifies a stored author" do
    author = OpenBlog::Author.create!(name: "Existing", slug: "existing")
    post "/blog/api/v1/posts", params: content.merge(author: author.id), as: :json
    assert_error 422, "validation_failed", [ "author" ]
    assert_equal 0, OpenBlog::Post.count
  end

  test "nested connection declarations reject nonstring identities and invalid dates" do
    input = { connections: [ { party: "Club", relation: "Member" } ], third_party_paid: false, declared_by: "Avery" }
    [ { declared_by: 123 }, { declared_on: "2026-10-03junk" }, { declared_on: "2026-02-31" },
      { connections: [ { party: 123, relation: "Member" } ] } ].each do |invalid|
      post "/blog/api/v1/posts", params: content.merge(connections: input.merge(invalid)), as: :json
      assert_response :unprocessable_entity
      assert_equal "validation_failed", response.parsed_body.dig("error", "code")
    end
    assert_equal 0, OpenBlog::Post.count
  end

  private

  def content
    { title: "Seed starting", body_format: "markdown", body: "Start with good seeds.", author: "Avery" }
  end

  def assert_error(status, code, details = [])
    assert_response status
    assert_equal code, response.parsed_body.dig("error", "code")
    assert_equal details, response.parsed_body.dig("error", "details")
    assert_includes response.headers["Cache-Control"], "no-store"
  end
end
