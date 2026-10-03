require_relative "test_helper"

class ReaderViewsTest < ActionDispatch::IntegrationTest
  setup do
    @saved_config = OpenBlog.config
    OpenBlog.instance_variable_set(:@config, @saved_config.deep_dup)
    OpenBlog.config.policy_urls = { responsible_party: "https://publisher.example/about" }
    OpenBlog.config.call_to_action = { title: "Grow with us", text: "A monthly planting letter.", url: "https://publisher.example/join", label: "Join the letter" }
    @author = OpenBlog::Author.create!(name: "Morgan Reed", slug: "morgan-reed", bio: "Writes about small gardens.", profile_urls: [ "https://people.example/morgan" ])
    @category = OpenBlog::Category.create!(name: "Small gardens", slug: "small-gardens")
    @tag = OpenBlog::Tag.create!(name: "Containers", slug: "containers")
    @post = make_post("potting-guide", featured: true)
    @post.tags << @tag
  end

  teardown { OpenBlog.instance_variable_set(:@config, @saved_config) }

  test "post components have one ordered content boundary and supporting sections outside" do
    image = OpenBlog::Image.create!(sha256: "c" * 64, filename: "planter.png", content_type: "image/png", byte_size: 3, width: 800, height: 400)
    @post.update!(cover_image: image, cover_alt: "A clay planter")
    @post.connection_declarations.create!(declared_on: Date.current, declared_by: "Morgan", connections: [], third_party_paid: true)
    @post.publications.create!(revision: @post.public_revision, entry_type: "correction", occurred_at: 1.hour.ago, note: "Corrected the pot size.")
    make_post("more-pots")
    get @post.path
    assert_response :success
    doc = document
    article = doc.at_css("article[data-open-blog-content]")
    assert article
    selectors = [ "h1", ".ob-lede", ".ob-notice--ai", ".ob-highlights", ".ob-byline", ".ob-cover", ".ob-toc", ".ob-disclosure", "[data-open-blog-body]", ".ob-correction" ]
    nodes = selectors.map { |selector| article.at_css(selector).tap { |node| assert node, selector } }
    assert_equal nodes, article.css(selectors.join(",")).to_a
    assert_equal article.at_css("[data-open-blog-body]"), article.at_css(".ob-disclosure").next_element
    outside = %w[.ob-breadcrumbs .ob-tags .ob-share .ob-responsible-party .ob-author-box .ob-call-to-action .ob-related-posts]
    outside.each do |selector|
      assert doc.at_css(selector), selector
      assert_empty article.css(selector), selector
    end
    assert_equal image.path, article.at_css(".ob-cover img")["src"]
    assert_equal "800", article.at_css(".ob-cover img")["width"]
    assert_empty article.css('img[src*="representations"]')
  end

  test "index has a featured post once twelve other cards and published sidebar counts" do
    13.times { |i| make_post("garden-#{i}") }
    make_post("draft-garden", status: "draft")
    get "/blog"
    assert_response :success
    assert_select ".ob-featured-card", count: 1
    assert_select ".ob-featured-card h2 a[href=?]", @post.path, count: 1
    assert_select ".ob-post-grid .ob-post-card", count: 12
    assert_select ".ob-post-grid a[href=?]", @post.path, count: 0
    assert_select ".ob-sidebar-categories a[href=?] .ob-count", "/blog/category/small-gardens", text: "14"
    assert_select ".ob-pagination a[href$='?page=2']"
    get "/blog", params: { page: 2 }
    assert_select ".ob-post-grid .ob-post-card", count: 1
    assert_select ".ob-featured-card", count: 1
  end

  test "reader pages have accessible headings localized copy and working blog links" do
    paths = [ "/blog", @post.path, "/blog/category/small-gardens", "/blog/tag/containers", "/blog/author/morgan-reed" ]
    links = []
    paths.each do |path|
      get path
      assert_response :success, path
      doc = document
      assert_equal 1, doc.css("h1").length, path
      assert_equal OpenBlog.config.locale.to_s.tr("_", "-"), doc.at_css("html")["lang"]
      levels = doc.css("h1,h2,h3,h4,h5,h6").map { |node| node.name.delete_prefix("h").to_i }
      levels.each_cons(2) { |left, right| assert right <= left + 1, "#{path}: h#{left} followed by h#{right}" }
      assert_empty doc.css("img:not([alt])"), path
      refute_includes response.body, "Translation missing"
      links.concat(doc.css('a[href^="/blog"]').map { |node| node["href"] })
    end
    assert_includes links, "/blog/author/morgan-reed"
    assert_includes links, "/blog/feed.xml"
    links.uniq.each do |path|
      get path
      assert_includes [ 200, 301, 302 ], response.status, path
    end
  end

  test "author and empty taxonomy pages expose their own content" do
    get "/blog/author/morgan-reed"
    assert_select "h1", text: "Morgan Reed"
    assert_select ".ob-author-bio", text: "Writes about small gardens."
    assert_select ".ob-author-profiles a[href=?]", "https://people.example/morgan"
    assert_select ".ob-avatar--initials", text: "MO"
    empty = OpenBlog::Category.create!(name: "Ponds", slug: "ponds")
    get "/blog/category/#{empty.slug}"
    assert_response :success
    assert_select "h1", text: "Ponds"
    assert_select ".ob-empty", text: I18n.t("open_blog.lists.empty")
    assert_select ".ob-list-description", text: /Ponds/
  end

  test "missing and removed pages offer the newest six public posts" do
    7.times { |i| make_post("recent-#{i}") }
    make_post("private-note", status: "draft")
    OpenBlog::Redirect.create!(old_path: "/blog/retired", source: "removal", occurred_on: Date.current)
    { "/blog/absent" => 404, "/blog/retired" => 410 }.each do |path, status|
      get path
      assert_response status
      assert_select "h1", count: 1
      assert_select ".ob-post-card", count: 6
      assert_select '.ob-post-card a[href="/blog/private-note"]', count: 0
      assert_select '.ob-post-card h3 a[href="/blog/recent-6"]', count: 1
      assert_select '.ob-post-card h3 a[href="/blog/recent-0"]', count: 0
    end
  end

  private

  def document
    Nokogiri::HTML5(response.body)
  end

  def make_post(slug, **attributes)
    OpenBlog::Post.create!({ title: slug.humanize, slug: slug, description: "Plants for a compact home.",
      body_markdown: "## Choose a pot\n\nPick a deep pot.\n\n### Drainage\n\nLeave a hole.\n\n## Planting\n\nAdd compost.",
      author: @author, author_name: @author.name, category: @category, status: "published" }.merge(attributes))
  end
end
