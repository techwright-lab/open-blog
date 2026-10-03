require_relative "test_helper"
require "minitest/mock"

class PreviewTest < ActionDispatch::IntegrationTest
  setup do
    @settings = %i[authenticate preview_expires_in body_formats].to_h { |key| [ key, OpenBlog.config.public_send(key) ] }
    OpenBlog.config.body_formats = %i[markdown rich_text]
    OpenBlog.config.authenticate = ->(_) { OpenBlog::Actor.new(name: "Reader", scopes: [ "read" ]) }
    @post = OpenBlog::SaveDraft.call({ title: "Quiet garden", body: "## First\n\nSeeds.\n\n## Second\n\nWater.\n\n## Third\n\nWait.",
      faq: [ { question: "When?", answer: "In spring." } ] }, actor: "Editor").post
  end
  teardown { @settings.each { |key, value| OpenBlog.config.public_send("#{key}=", value) } }

  test "API preview and full post expose a signed expiring draft link with no database writes" do
    get "/blog/api/v1/posts/#{@post.id}/preview"
    assert_response :ok
    data = response.parsed_body
    assert_equal %w[expires_at preview_url revision_identifier], data.keys.sort
    assert_equal @post.current_revision_identifier, data["revision_identifier"]
    assert_in_delta 7.days.to_f, Time.iso8601(data["expires_at"]) - Time.current, 2
    assert_equal "no-store", response.headers["Cache-Control"]
    get "/blog/api/v1/posts/#{@post.id}"
    assert_response :ok
    assert_match %r{/blog/preview/}, response.parsed_body["preview_url"]
    OpenBlog.config.authenticate = nil
    get "/blog/api/v1/posts/#{@post.id}/preview"
    assert_response :unauthorized
    assert_preview(data["preview_url"])
  end

  test "preview uses real content without any application cache or database writes" do
    token = @post.preview_token
    writes = []
    listener = ->(*args) { sql = args.last[:sql]; writes << sql if sql.match?(/\A\s*(?:INSERT|UPDATE|DELETE)\b/i) }
    store = ActiveSupport::Cache::MemoryStore.new
    previous_store = OpenBlog::PreviewsController.cache_store
    previous_caching = OpenBlog::PreviewsController.perform_caching
    OpenBlog::PreviewsController.cache_store = store
    OpenBlog::PreviewsController.perform_caching = true
    store.stub(:fetch, ->(*) { flunk "preview used application cache" }) do
      store.stub(:write, ->(*) { flunk "preview wrote application cache" }) do
        Rails.stub(:cache, store) do
          ActiveSupport::Notifications.subscribed(listener, "sql.active_record") { get preview_path(token) }
        end
      end
    end
    assert_response :ok
    assert_empty writes
    assert_select "[data-open-blog-preview]", text: "Draft preview"
    assert_select "[data-open-blog-content] h1", text: "Quiet garden"
    assert_select "[data-open-blog-faq-entry] h3", text: "When?"
    assert_select 'meta[name=robots][content="noindex, nofollow"]', count: 1
    assert_select "link[rel=canonical]", count: 1 do |links|
      assert_equal @post.url, links.first["href"]
    end
    assert_select "head", text: /Quiet garden/
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal "no-referrer", response.headers["Referrer-Policy"]
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
    refute_includes response.body, token
  ensure
    OpenBlog::PreviewsController.cache_store = previous_store
    OpenBlog::PreviewsController.perform_caching = previous_caching
  end

  test "changed title body FAQ and image revision invalidates previous link" do
    image = OpenBlog::Image.create!(sha256: "c" * 64, filename: "preview.png", content_type: "image/png", byte_size: 1, width: 1, height: 1)
    [ { title: "Changed title" }, { body: "New text." }, { faq: [ { question: "Why?", answer: "Because." } ] }, { cover_image: { image_id: image.id } } ].each do |attributes|
      token = @post.reload.preview_token
      result = OpenBlog::SaveDraft.call(attributes, post: @post, actor: "Editor")
      assert result.success?, result.error&.message
      get preview_path(token)
      assert_stopped
      refute_equal token, @post.reload.preview_token
    end
  end

  test "expired tampered removed and duration changed links stop" do
    token = @post.preview_token
    travel 8.days do
      get preview_path(token)
      assert_stopped
    end
    get preview_path("not-valid")
    assert_stopped
    OpenBlog.config.preview_expires_in = 1.hour
    get preview_path(token)
    assert_stopped
    fresh = @post.preview_token
    assert_preview(preview_path(fresh))
    OpenBlog::Remove.call(@post, actor: "Editor")
    get preview_path(fresh)
    assert_stopped
  end

  test "scheduled drafts keep previews and publication redirects an unchanged token" do
    token = @post.preview_token
    result = OpenBlog::Publish.call({ publish_at: 1.day.from_now.iso8601 }, post: @post, actor: "Editor")
    assert result.success?
    get "/blog/api/v1/posts/#{@post.id}/preview"
    assert_response :ok
    get "/blog/api/v1/posts/#{@post.id}"
    assert_match %r{/preview/}, response.parsed_body["preview_url"]
    assert_preview(preview_path(token))
    result = OpenBlog::Publish.call({}, post: @post, actor: "Editor")
    assert result.success?
    get preview_path(token)
    assert_response :found
    assert_redirected_to @post.path
    assert_equal "no-store", response.headers["Cache-Control"]
    get "/blog/api/v1/posts/#{@post.id}/preview"
    assert_response :not_found
    get "/blog/api/v1/posts/#{@post.id}"
    assert_nil response.parsed_body["preview_url"]
    OpenBlog::Remove.call(@post, actor: "Editor")
    get preview_path(token)
    assert_stopped
    get "/blog/api/v1/posts/#{@post.id}/preview"
    assert_response :not_found
  end

  test "draft previews do not appear in public lists feeds or sitemaps" do
    get "/blog/feed.xml"
    refute_includes response.body, @post.title
    get "/blog/sitemap.xml"
    refute_includes response.body, @post.path
    get "/blog"
    refute_includes response.body, @post.title
    assert_empty OpenBlog.sitemap_entries.select { |entry| entry[:url] == @post.url }
  end

  test "preview lifetime requires a positive finite duration" do
    [ nil, 0, -1, Float::INFINITY, "7.days" ].each do |value|
      OpenBlog.config.preview_expires_in = value
      assert_raises(OpenBlog::ConfigurationError) { OpenBlog.config.validate_structure! }
    end
  end

  test "preview bypasses host reader authentication callbacks" do
    callback = -> { head :unauthorized }
    OpenBlog::ApplicationController.before_action(callback)
    get "/blog"
    assert_response :unauthorized
    assert_preview(preview_path(@post.preview_token))
  ensure
    OpenBlog::ApplicationController.skip_before_action(callback)
  end

  test "short configured token lifetimes and conditional requests do not cache previews" do
    OpenBlog.config.preview_expires_in = 1.minute
    token = @post.preview_token
    get preview_path(token)
    assert_response :ok
    etag = response.headers["ETag"]
    get preview_path(token), headers: { "If-None-Match" => etag.to_s }
    assert_response :ok
    travel 61.seconds do
      get preview_path(token), headers: { "If-None-Match" => etag.to_s }
      assert_stopped
    end
  end

  private

  def preview_path(token)
    "/blog/preview/#{ERB::Util.url_encode(token)}"
  end

  def assert_preview(url)
    get url
    assert_response :ok
    assert_select "[data-open-blog-preview]", text: "Draft preview"
  end

  def assert_stopped
    assert_response :not_found
    assert_select "h1", text: "This preview link has stopped"
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_select 'meta[name=robots][content="noindex, nofollow"]', count: 1
  end
end
