require_relative "test_helper"

class ReaderConsistencyTest < ActionDispatch::IntegrationTest
  setup do
    @author = OpenBlog::Author.create!(name: "Robin Green", slug: "robin-green")
    @category = OpenBlog::Category.create!(name: "Kitchen gardens", slug: "kitchen-gardens")
    @post = OpenBlog::Post.create!(title: "Growing herbs", slug: "growing-herbs", category: @category,
      body_markdown: "## Planting\n\nStart with fresh soil.", status: "published", author: @author, author_name: @author.name)
  end

  test "reader requests do not write records" do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("Unprocessed image bytes"), filename: "herbs.png", content_type: "image/png", identify: false)
    image = OpenBlog::Image.new(sha256: "e" * 64, filename: "herbs.png", content_type: "image/png", byte_size: blob.byte_size, width: 800, height: 400)
    image.file = blob
    image.save!
    @author.avatar.attach(blob)
    @post.update!(cover_image: image, cover_alt: "Potted herbs")
    writes = []
    callback = ->(_name, _start, _finish, _id, payload) do
      writes << payload[:sql] if payload[:sql].match?(/\A\s*(?:INSERT|UPDATE|DELETE)\b/i)
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      [ "/blog", @post.path, "/blog/category/kitchen-gardens", "/blog/feed.xml", "/blog/sitemap.xml" ].each do |path|
        get path
        assert_response :success, path
        assert_select ".ob-card-image[src*='/representations/']" if path == "/blog"
      end
    end
    assert_empty writes
  ensure
    blob&.service&.delete(blob.key)
  end

  test "sidebar rename invalidates cached output without a post count or date change" do
    with_fragment_cache do
      get "/blog"
      assert_response :success
      assert_select ".ob-sidebar", text: /Kitchen gardens/
      old_etag = response.headers["ETag"]
      assert old_etag.present?
      @category.update!(name: "Small gardens")
      get "/blog", headers: { "If-None-Match" => old_etag }
      assert_response :success
      assert_select ".ob-sidebar", text: /Small gardens/
      refute_includes response.body, "Kitchen gardens"
    end
  end

  test "related card metadata changes invalidate a cached post response" do
    related = OpenBlog::Post.create!(title: "Growing thyme", slug: "growing-thyme", category: @category,
      body_markdown: "Choose a sunny spot.", status: "published", author: @author, author_name: @author.name)
    with_fragment_cache do
      get @post.path
      assert_response :success
      assert_select ".ob-related-posts", text: /Kitchen gardens/
      old_etag = response.headers["ETag"]
      assert old_etag.present?
      @category.update!(name: "Container gardens")
      get @post.path, headers: { "If-None-Match" => old_etag }
      assert_response :success
      assert_select ".ob-related-posts", text: /Container gardens/
      assert_select ".ob-related-posts a[href='#{related.path}']"
    end
  end

  test "storage timestamps never become reader publication dates" do
    get @post.path
    assert_response :success
    before = date_output
    OpenBlog::Post.where(id: @post.id).update_all(updated_at: 10.years.from_now)
    get @post.path
    assert_response :success
    assert_equal before, date_output
  end

  private

  def date_output
    html = Nokogiri::HTML5(response.body)
    { times: html.css("time").map { |node| [ node["datetime"], node.text ] },
      article: html.css("meta[property^='article:']").map { |node| [ node["property"], node["content"] ] },
      schema: JSON.parse(html.at_css("script[type='application/ld+json']").text) }
  end

  def with_fragment_cache
    previous_cache = Rails.cache
    previous_controller_cache = OpenBlog::ApplicationController.cache_store
    previous_caching = OpenBlog::ApplicationController.perform_caching
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    OpenBlog::ApplicationController.cache_store = Rails.cache
    OpenBlog::ApplicationController.perform_caching = true
    yield
  ensure
    Rails.cache = previous_cache
    OpenBlog::ApplicationController.cache_store = previous_controller_cache
    OpenBlog::ApplicationController.perform_caching = previous_caching
  end
end
