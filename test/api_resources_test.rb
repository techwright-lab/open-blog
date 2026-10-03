require_relative "test_helper"
require "zlib"

class ApiResourcesTest < ActionDispatch::IntegrationTest
  setup do
    @hook = OpenBlog.config.authenticate
    @scopes = %w[read write publish]
    OpenBlog.config.authenticate = ->(_) { OpenBlog::Actor.new(name: "Catalog editor", scopes: @scopes) }
  end
  teardown { OpenBlog.config.authenticate = @hook }

  test "taxonomy writes and lists expose explicit objects and typed validation" do
    post "/blog/api/v1/categories", params: { name: "Field notes", description: "Seasonal observations", position: 2 }, as: :json
    assert_response :created
    assert_equal %w[description id name position posts_count slug], response.parsed_body.keys.sort
    id = response.parsed_body["id"]
    patch "/blog/api/v1/categories/#{id}", params: { description: "Updated introduction" }, as: :json
    assert_response :ok
    get "/blog/api/v1/categories", params: { per_page: 500 }
    assert_equal %w[categories page per_page total], response.parsed_body.keys.sort
    assert_equal 100, response.parsed_body["per_page"]
    assert_equal "Updated introduction", response.parsed_body["categories"].first["description"]
    post "/blog/api/v1/categories", params: { name: "Huge position", position: 2**63 }, as: :json
    assert_error 422, "validation_failed"
    post "/blog/api/v1/categories", params: { name: "Field notes" }, as: :json
    assert_error 422, "validation_failed"
    post "/blog/api/v1/authors", params: { name: "Field Society", type: "organization", profile_urls: [ "https://example.test/about" ], bio: "Our team" }, as: :json
    assert_response :created
    assert_equal %w[avatar bio host_reference id name posts_count profile_urls slug type url], response.parsed_body.keys.sort
    assert_equal "organization", response.parsed_body["type"]
    post "/blog/api/v1/series", params: { name: "Four seasons", description: "Annual notes" }, as: :json
    assert_response :created
    assert_equal %w[description id name posts slug], response.parsed_body.keys.sort
    get "/blog/api/v1/tags"
    assert_response :ok
    assert_equal %w[page per_page tags total], response.parsed_body.keys.sort
    post "/blog/api/v1/authors", params: { name: 123 }, as: :json
    assert_error 422, "validation_failed"
  end

  test "redirects collapse chains refuse cycles and preserve dated history" do
    post "/blog/api/v1/redirects", params: { old_path: "/blog/older", new_path: "/blog/newer", occurred_on: "2025-01-02" }, as: :json
    assert_response :created
    first_id = response.parsed_body["id"]
    assert_equal %w[id new_path occurred_on old_path post_id source], response.parsed_body.keys.sort
    post "/blog/api/v1/redirects", params: { old_path: "/blog/newer", new_path: "/blog/current" }, as: :json
    assert_response :created
    assert_equal "/blog/current", OpenBlog::Redirect.find(first_id).new_path
    assert_equal Date.new(2025, 1, 2), OpenBlog::Redirect.find(first_id).occurred_on
    post "/blog/api/v1/redirects", params: { old_path: "/blog/current", new_path: "/blog/older" }, as: :json
    assert_error 422, "validation_failed"
    post "/blog/api/v1/redirects", params: { old_path: "/blog/bad", new_path: "javascript:alert(1)" }, as: :json
    assert_error 422, "validation_failed"
    live = OpenBlog::Publish.call({ title: "Occupied route" }, actor: "Editor").post
    post "/blog/api/v1/redirects", params: { old_path: live.path, new_path: "/elsewhere" }, as: :json
    assert_error 409, "slug_reserved"
    post "/blog/api/v1/redirects", params: { old_path: "/blog/gone", new_path: nil }, as: :json
    assert_response :created
    delete "/blog/api/v1/redirects/#{response.parsed_body['id']}"
    assert_response :no_content
  end

  test "adoption dry run retains candidate approvals and exact record envelope without writes" do
    input = { source_system: "archive", source_id: "field-1", slug: "field-notes", title: "Field notes", body_format: "markdown", body: "A quiet field.", dry_run: true,
      declaration: { reviewer_name: "Casey", facts_checked: true, approved_at: "2025-03-01T10:00:00Z", declared_on: "2026-10-03", declared_by: "Publisher" } }
    assert_no_difference [ "OpenBlog::Post.count", "OpenBlog::Approval.count", "OpenBlog::Baseline.count" ] do
      post "/blog/api/v1/adoptions", params: input, as: :json
    end
    assert_response :created
    assert_equal %w[created dry_run findings post records], response.parsed_body.keys.sort
    assert_equal true, response.parsed_body.dig("post", "approved")
    assert_equal %w[approval baseline publication redirects revision], response.parsed_body["records"].keys.sort
    assert_equal "new", response.parsed_body.dig("records", "baseline")
    assert_equal true, response.parsed_body["dry_run"]
    post "/blog/api/v1/adoptions", params: input.merge(dry_run: false), as: :json
    assert_response :created
    post "/blog/api/v1/adoptions", params: input.merge(dry_run: false), as: :json
    assert_response :ok
    assert_equal false, response.parsed_body["created"]
    post "/blog/api/v1/adoptions", params: input.merge(approval: {}), as: :json
    assert_error 422, "unknown_field"
  end

  test "extraction returns original text slices without storing records" do
    assert_no_difference "OpenBlog::Post.count" do
      post "/blog/api/v1/faq_extractions", params: { body: "Intro.\n\n## FAQ\n\n### When?\n\nAt dawn.\n" }, as: :json
    end
    assert_response :ok
    assert_equal %w[body_after class cut leftover pairs reasons source_body_sha256], response.parsed_body.keys.sort
    assert_equal [ { "question" => "When?", "answer" => "At dawn." } ], response.parsed_body["pairs"]
    assert_equal "clean", response.parsed_body["class"]
  end

  test "avatar imports reuse the blob and reads never import native avatars" do
    bytes = "\x89PNG\r\n\x1a\n".b + png_chunk("IHDR", [ 2, 3, 8, 2, 0, 0, 0 ].pack("NNC5")) +
      png_chunk("IDAT", Zlib::Deflate.deflate(("\0".b + "\x12\x34\x56".b * 2) * 3)) + png_chunk("IEND", "".b)
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(bytes), filename: "portrait.png", content_type: "image/png", identify: false)
    native = OpenBlog::Author.create!(name: "Native author")
    native.avatar.attach(blob)
    assert_no_difference "OpenBlog::Image.count" do
      get "/blog/api/v1/authors"
      assert_nil response.parsed_body["authors"].find { |row| row["id"] == native.id }["avatar"]
    end
    assert_no_difference [ "OpenBlog::Image.count", "ActiveStorage::Blob.count", "ActiveStorage::Attachment.count" ] do
      post "/blog/api/v1/authors", params: { name: "", avatar: { signed_id: blob.signed_id } }, as: :json
      assert_error 422, "validation_failed"
    end
    assert_no_difference "ActiveStorage::Blob.count" do
      patch "/blog/api/v1/authors/#{native.id}", params: { name: "Renamed author", avatar: { signed_id: blob.signed_id } }, as: :json
      assert_response :ok
    end
    image_id = response.parsed_body.dig("avatar", "image_id")
    assert image_id
    assert_equal blob.id, native.reload.avatar.blob.id
    assert_equal "Renamed author", native.name
    patch "/blog/api/v1/authors/#{native.id}", params: { avatar: nil }, as: :json
    assert_response :ok
    assert_nil response.parsed_body["avatar"]
    assert OpenBlog::Image.exists?(image_id)
  ensure
    blob&.service&.delete(blob.key)
  end

  test "adoption optional declaration date uses supplied operation time" do
    input = { source_system: "archive", source_id: "dated-1", slug: "dated-note", title: "Dated note", body_format: "markdown", body: "Note.",
      connections: { connections: [], third_party_paid: false, declared_by: "Publisher" } }
    travel_to Time.zone.parse("2026-10-04 10:00:00") do
      post "/blog/api/v1/adoptions", params: input.merge(connections: input[:connections].merge(declared_on: "2026-10-04junk")), as: :json
      assert_error 422, "validation_failed"
      post "/blog/api/v1/adoptions", params: input, as: :json
      assert_response :created
      assert_equal Date.current, OpenBlog::Post.find(response.parsed_body.dig("post", "id")).connection_declarations.last.declared_on
    end
  end

  test "all resource methods enforce authentication and scopes" do
    category = OpenBlog::Category.create!(name: "Existing category")
    author = OpenBlog::Author.create!(name: "Existing author")
    series = OpenBlog::Series.create!(name: "Existing series")
    redirect = OpenBlog::Redirect.create!(old_path: "/old", new_path: nil, source: "manual", occurred_on: Date.current)
    endpoints = [
      [ :get, "categories", "read" ], [ :post, "categories", "write" ], [ :patch, "categories/#{category.id}", "write" ],
      [ :get, "authors", "read" ], [ :post, "authors", "write" ], [ :patch, "authors/#{author.id}", "write" ],
      [ :get, "series", "read" ], [ :post, "series", "write" ], [ :patch, "series/#{series.id}", "write" ],
      [ :get, "tags", "read" ], [ :get, "redirects", "read" ], [ :post, "redirects", "publish" ],
      [ :delete, "redirects/#{redirect.id}", "publish" ], [ :post, "adoptions", "publish" ], [ :post, "faq_extractions", "read" ]
    ]
    revoked, secret = OpenBlog::ApiToken.generate(name: "Revoked")
    revoked.update!(revoked_at: Time.current)
    _expired, expired_secret = OpenBlog::ApiToken.generate(name: "Expired", expires_at: 1.minute.ago)
    endpoints.each do |method, path, scope|
      OpenBlog.config.authenticate = nil
      [ nil, secret, expired_secret ].each do |token|
        public_send(method, "/blog/api/v1/#{path}", headers: token ? { "Authorization" => "Bearer #{token}" } : {}, as: :json)
        assert_error 401, "unauthenticated"
      end
      @scopes = []
      OpenBlog.config.authenticate = ->(_) { OpenBlog::Actor.new(name: "Catalog editor", scopes: @scopes) }
      public_send(method, "/blog/api/v1/#{path}", as: :json)
      assert_error 403, "scope_required"
      assert_equal [ scope ], response.parsed_body.dig("error", "details")
    end
  end

  test "taxonomy counts include drafts and series entries are position ordered" do
    first = OpenBlog::SaveDraft.call({ title: "Second entry", category: "Meadows", tags: [ "Walking" ], series: "Trails", series_position: 2 }, actor: "Writer").post
    second = OpenBlog::SaveDraft.call({ title: "First entry", category: "Meadows", tags: [ "Walking" ], series: "Trails", series_position: 1 }, actor: "Writer").post
    get "/blog/api/v1/categories"
    assert_equal 2, response.parsed_body["categories"].first["posts_count"]
    get "/blog/api/v1/tags"
    assert_equal %w[id name posts_count slug], response.parsed_body["tags"].first.keys.sort
    assert_equal 2, response.parsed_body["tags"].first["posts_count"]
    get "/blog/api/v1/authors"
    assert_equal 2, response.parsed_body["authors"].first["posts_count"]
    get "/blog/api/v1/series"
    assert_equal [ second.id, first.id ], response.parsed_body["series"].first["posts"].pluck("id")
    assert_equal %w[id position slug title], response.parsed_body["series"].first["posts"].first.keys.sort
    patch "/blog/api/v1/series/#{first.series_id}", params: { description: "A sequence" }, as: :json
    assert_response :ok
    assert_equal "A sequence", response.parsed_body["description"]
    get "/blog/api/v1/categories", params: { page: "-1" }
    assert_error 422, "validation_failed"
    post "/blog/api/v1/series", params: { name: "Hidden", admin: true }, as: :json
    assert_error 422, "unknown_field"
    post "/blog/api/v1/redirects", params: { old_path: "/bad", occurred_on: "2026-02-30" }, as: :json
    assert_error 422, "validation_failed"
  end

  test "adoption refusals do not silently accept unknown nested values or replace later publications" do
    input = { source_system: "archive", source_id: "old-1", slug: "old-note", title: "Old note", body_format: "markdown", body: "Original." }
    post "/blog/api/v1/adoptions", params: input.merge(faq: [ { question: "When?", answer: "Today", extra: true } ]), as: :json
    assert_error 422, "unknown_field"
    assert_equal [ "faq.extra" ], response.parsed_body.dig("error", "details")
    post "/blog/api/v1/adoptions", params: input.merge(slug: "Old.Note"), as: :json
    assert_error 422, "slug_not_supported"
    post "/blog/api/v1/adoptions", params: input, as: :json
    assert_response :created
    adopted = OpenBlog::Post.find(response.parsed_body.dig("post", "id"))
    OpenBlog::Publish.call({ body: "An amendment.", change: "substantive" }, post: adopted, actor: "Editor")
    post "/blog/api/v1/adoptions", params: input.merge(body: "Replacement."), as: :json
    assert_error 409, "already_changed_in_gem"
    assert_equal "An amendment.", adopted.reload.body_markdown
  end

  private

  def png_chunk(type, data)
    [ data.bytesize ].pack("N") + type + data + [ Zlib.crc32(type + data) ].pack("N")
  end

  def assert_error(status, code)
    assert_response status
    assert_equal code, response.parsed_body.dig("error", "code")
    assert_kind_of Array, response.parsed_body.dig("error", "details")
    assert_equal "no-store", response.headers["Cache-Control"]
  end
end
