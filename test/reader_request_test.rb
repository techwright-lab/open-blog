require_relative "test_helper"

class ReaderRequestTest < ActionDispatch::IntegrationTest
  setup do
    @author = OpenBlog::Author.create!(name: "Avery Fields", slug: "avery-fields")
    @category = OpenBlog::Category.create!(name: "Green spaces", slug: "green-spaces")
    @tag = OpenBlog::Tag.create!(name: "Balcony", slug: "balcony")
    @post = OpenBlog::Post.create!(title: "Balcony planting", slug: "balcony-planting", body_markdown: "## Start\n\nChoose a sunny spot.",
      author: @author, author_name: @author.name, category: @category, status: "published")
    @post.tags << @tag
  end

  test "public routes resolve and explicit unsupported formats stay unavailable" do
    [ "/blog", @post.path, "/blog/category/green-spaces", "/blog/tag/balcony", "/blog/author/avery-fields" ].each do |path|
      get path
      assert_response :success, path
      assert_equal "text/html", response.media_type
    end
    get @post.path, headers: { "Accept" => "application/json" }
    assert_response :success
    assert_equal "text/html", response.media_type
    get "#{@post.path}.json"
    assert_response :not_found
    get "#{@post.path}.md"
    assert_response :success
    assert_equal "text/markdown", response.media_type
    get "/blog/search"
    assert_response :success
  end

  test "published pages take precedence then redirects then missing pages" do
    OpenBlog::Redirect.create!(old_path: @post.path, new_path: "/blog/other", source: "manual", occurred_on: Date.current)
    get @post.path
    assert_response :success
    OpenBlog::Redirect.create!(old_path: "/blog/older", new_path: @post.path, source: "manual", occurred_on: Date.current)
    get "/blog/older"
    assert_response :moved_permanently
    assert_redirected_to @post.path
    OpenBlog::Redirect.create!(old_path: "/blog/removed", source: "manual", occurred_on: Date.current)
    get "/blog/removed"
    assert_response :gone
    get "/blog/absent"
    assert_response :not_found
    OpenBlog::Redirect.where(old_path: @post.path).delete_all
    @post.update!(status: "draft")
    get @post.path
    assert_response :not_found
  end

  test "page numbers are validated and a featured post is excluded from page counts" do
    @post.update!(featured: true)
    13.times do |index|
      OpenBlog::Post.create!(title: "Planting note #{index}", slug: "planting-note-#{index}", body_markdown: "A short note.",
        author: @author, author_name: @author.name, status: "published")
    end
    get "/blog", params: { page: 2 }
    assert_response :success
    assert_select "link[rel=canonical][href$='?page=2']", count: 1
    %w[0 -1 words 1.5 99].each do |page|
      get "/blog", params: { page: page }
      assert_response :not_found, page
    end
  end

  test "feeds have stable identities scoped posts and publication dates" do
    get "/blog/feed.xml"
    assert_response :success
    assert_equal "application/atom+xml", response.media_type
    assert_includes response.headers["Cache-Control"], "max-age=3600"
    xml = Nokogiri::XML(response.body) { |config| config.strict }
    ns = { "a" => "http://www.w3.org/2005/Atom" }
    assert_empty xml.errors
    schema = Nokogiri::XML::RelaxNG(File.read(File.expand_path("fixtures/schemas/atom.rng", __dir__)))
    assert_empty schema.validate(xml)
    invalid = xml.dup
    invalid.at_xpath("/a:feed/a:entry/a:id", ns).remove
    refute_empty schema.validate(invalid)
    %w[id title updated link].each { |name| assert xml.at_xpath("/a:feed/a:#{name}", ns), name }
    xml.xpath("/a:feed/a:entry", ns).each do |entry|
      %w[id title updated link author].each { |name| assert entry.at_xpath("a:#{name}", ns), name }
      assert entry.at_xpath("a:author/a:name", ns)
      assert Time.iso8601(entry.at_xpath("a:updated", ns).text)
    end
    assert_equal OpenBlog.config.public_base_url + "/blog", xml.at_xpath("/a:feed/a:id", ns).text
    assert_equal @post.url, xml.at_xpath("/a:feed/a:entry/a:id", ns).text
    assert_equal @post.modified_at.iso8601, xml.at_xpath("/a:feed/a:entry/a:updated", ns).text
    assert_equal @post.description, xml.at_xpath("/a:feed/a:entry/a:summary", ns).text
    get "/blog/category/green-spaces/feed.xml"
    assert_response :success
    assert_equal 1, Nokogiri::XML(response.body).xpath("//a:entry", ns).length
  end

  test "empty and full-content Atom feeds validate without external schema requests" do
    previous = OpenBlog.config.feed_content
    schema = Nokogiri::XML::RelaxNG(File.read(File.expand_path("fixtures/schemas/atom.rng", __dir__)))
    OpenBlog.config.feed_content = :full
    get "/blog/feed.xml"
    assert_response :success
    xml = Nokogiri::XML(response.body)
    assert_empty schema.validate(xml)
    content = xml.at_xpath("//a:content", "a" => "http://www.w3.org/2005/Atom")
    assert_includes content.text, "Choose a sunny spot."
    @post.update!(status: "draft")
    get "/blog/feed.xml"
    assert_response :success
    xml = Nokogiri::XML(response.body)
    assert_empty schema.validate(xml)
    assert_empty xml.xpath("//a:entry", "a" => "http://www.w3.org/2005/Atom")
  ensure
    OpenBlog.config.feed_content = previous
  end

  test "sitemap follows primary taxonomy and excludes off-site canonicals" do
    previous = OpenBlog.config.primary_list_type
    entries = OpenBlog.sitemap_entries
    assert_includes entries.pluck(:loc), @post.url
    assert_includes entries.pluck(:loc), OpenBlog.config.public_base_url + "/blog/category/green-spaces"
    refute_includes entries.pluck(:loc), OpenBlog.config.public_base_url + "/blog/tag/balcony"
    OpenBlog.config.primary_list_type = :tags
    entries = OpenBlog.sitemap_entries
    assert_includes entries.pluck(:loc), OpenBlog.config.public_base_url + "/blog/tag/balcony"
    refute_includes entries.pluck(:loc), OpenBlog.config.public_base_url + "/blog/category/green-spaces"
    @post.update!(canonical_url: "https://outside.example/planting")
    refute_includes OpenBlog.sitemap_entries.pluck(:loc), @post.url
    get "/blog/sitemap.xml"
    assert_response :success
    assert_equal "application/xml", response.media_type
  ensure
    OpenBlog.config.primary_list_type = previous
  end

  test "sitemap explicit origins reject credentials paths fragments and malformed values" do
    [ "https://user:secret@example.test", "https://example.test/path", "https://example.test/?page=1",
      "https://example.test/#section", "https://example.test//", "mailto:reader@example.test", "not a URL", 123 ].each do |base|
      assert_raises(OpenBlog::ConfigurationError, base.inspect) { OpenBlog.sitemap_entries(base_url: base) }
    end
    assert OpenBlog.sitemap_entries(base_url: "https://reader.example/").all? { |entry| entry[:loc].start_with?("https://reader.example/blog") }
  end

  test "sitemap requires a configured origin outside requests and uses request fallback" do
    previous = OpenBlog.config.public_base_url
    OpenBlog.config.public_base_url = nil
    assert_raises(OpenBlog::ConfigurationError) { OpenBlog.sitemap_entries }
    assert OpenBlog.sitemap_entries(base_url: "https://reader.example").all? { |entry| entry[:loc].start_with?("https://reader.example/") }
    get "/blog/sitemap.xml"
    assert_response :success
    assert_includes response.body, "http://www.example.com/blog"
  ensure
    OpenBlog.config.public_base_url = previous
  end
end
