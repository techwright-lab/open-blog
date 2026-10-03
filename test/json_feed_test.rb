require_relative "test_helper"

class JsonFeedTest < ActionDispatch::IntegrationTest
  setup do
    @settings = %i[feed_content feed_size public_base_url].to_h { |field| [ field, OpenBlog.config.public_send(field) ] }
    OpenBlog.config.feed_content = :summary
    OpenBlog.config.feed_size = 2
  end
  teardown { @settings.each { |field, value| OpenBlog.config.public_send("#{field}=", value) } }

  test "JSON Feed 1.1 includes required content and stable absolute item identities" do
    first = publish("First trail", category: "Walking", description: "A short route.")
    second = publish("Second trail", category: "Cycling", description: "A longer route.")
    publish("Third trail", category: "Walking", description: "A quiet route.")
    OpenBlog::SaveDraft.call({ title: "Private route" }, actor: "Editor")
    get "/blog/feed.json", headers: { "Accept" => "text/html" }
    assert_response :ok
    assert_equal "application/feed+json", response.media_type
    assert_includes response.headers["Cache-Control"], "public"
    assert_includes response.headers["Cache-Control"], "max-age=3600"
    feed = JSON.parse(response.body)
    assert_equal "https://jsonfeed.org/version/1.1", feed["version"]
    assert_kind_of String, feed["title"]
    assert_equal "https://example.test/blog", feed["home_page_url"]
    assert_equal "https://example.test/blog/feed.json", feed["feed_url"]
    assert_equal 2, feed["items"].size
    feed["items"].each do |item|
      assert_kind_of String, item["id"]
      assert_equal item["url"], item["id"]
      assert_match %r{\Ahttps://example.test/blog/}, item["url"]
      assert_equal item["summary"], item["content_text"]
      assert item["authors"].first["name"].present?
      Time.iso8601(item.fetch("date_published"))
      Time.iso8601(item.fetch("date_modified"))
    end
    get "/blog/category/walking/feed.json"
    assert_response :ok
    assert_equal "Walking", JSON.parse(response.body)["title"]
    assert_equal "https://example.test/blog/category/walking/feed.json", JSON.parse(response.body)["feed_url"]
    assert_includes JSON.parse(response.body)["items"].pluck("url"), first.url
    refute_includes JSON.parse(response.body)["items"].pluck("url"), second.url
    get "/blog/category/missing/feed.json"
    assert_response :not_found
  end

  test "full feeds render sanitized HTML and remain valid JSON with hostile text" do
    post = publish('A "quoted" title </script>', description: "Plain <summary>", body: "## Route\n\n<script>alert('bad')</script>\n\n**A strong start.**")
    OpenBlog.config.feed_content = :full
    get "/blog/feed.json"
    assert_response :ok
    item = JSON.parse(response.body).fetch("items").first
    assert_equal post.title, item["title"]
    assert_equal "Plain <summary>", item["summary"]
    assert_includes item["content_html"], "<strong>A strong start.</strong>"
    refute_includes item["content_html"], "<script>"
    refute item.key?("content_text")
  end

  test "adopted unknown dates use adoption for modified without inventing publication" do
    now = Time.current.change(usec: 0)
    result = OpenBlog::Adopt.call({ source_system: "archive", source_id: "one", slug: "older-route", title: "Older route", body_format: "markdown", body: "An old route." }, actor: "Importer", now: now - 2.days)
    assert result.success?, result.error&.message
    post = result.post
    post.update_columns(updated_at: now)
    post.publications.create!(revision: post.public_revision, entry_type: "maintenance", occurred_at: now - 1.day)
    get "/blog/feed.json"
    item = JSON.parse(response.body).fetch("items").first
    refute item.key?("date_published")
    assert_equal (now - 2.days).iso8601, item["date_modified"]
    post.update_columns(published_at: now + 1.day, modified_at: now + 1.day)
    get "/blog/feed.json"
    item = JSON.parse(response.body).fetch("items").first
    refute item.key?("date_published")
    assert_equal (now - 2.days).iso8601, item["date_modified"]
  end

  test "reader heads advertise both feed formats with category scope" do
    post = publish("Trail map", category: "Routes")
    [ "/blog", post.path, "/blog/category/routes" ].each do |path|
      get path
      assert_response :ok
      doc = Nokogiri::HTML(response.body)
      suffix = path == "/blog/category/routes" ? "/blog/category/routes" : "/blog"
      assert_equal [ "https://example.test#{suffix}/feed.json" ], doc.css('link[rel="alternate"][type="application/feed+json"]').map { |node| node["href"] }
      assert_equal [ "https://example.test#{suffix}/feed.xml" ], doc.css('link[rel="alternate"][type="application/atom+xml"]').map { |node| node["href"] }
    end
  end

  test "empty feed is valid and serialization never writes content or storage rows" do
    get "/blog/feed.json"
    assert_response :ok
    assert_equal [], JSON.parse(response.body)["items"]
    assert_equal "https://jsonfeed.org/version/1.1", JSON.parse(response.body)["version"]
    publish("Read-only feed", body: "## A heading\n\nA paragraph.")
    OpenBlog.config.feed_content = :full
    writes = []
    observer = ->(_name, _start, _finish, _id, payload) { writes << payload[:sql] if payload[:sql].match?(/\A\s*(INSERT|UPDATE|DELETE)\b/i) }
    ActiveSupport::Notifications.subscribed(observer, "sql.active_record") { get "/blog/feed.json" }
    assert_response :ok
    assert_empty writes
  end

  test "request origin is used when the public origin is not configured" do
    OpenBlog.config.public_base_url = nil
    publish("Local feed")
    host! "reader.example"
    get "/blog/feed.json"
    assert_response :ok
    assert_equal "http://reader.example/blog/feed.json", JSON.parse(response.body)["feed_url"]
    assert_match %r{\Ahttp://reader.example/blog/}, JSON.parse(response.body)["items"].first["url"]
  end

  private

  def publish(title, **attributes)
    result = OpenBlog::Publish.call({ title: title, body: "A route through the woods." }.merge(attributes), actor: "Editor")
    assert result.success?, result.error&.message
    result.post
  end
end
