require_relative "test_helper"

class SeriesMarkdownTest < ActionDispatch::IntegrationTest
  setup do
    @author = OpenBlog::Author.create!(name: "Series author", slug: "series-author")
    @series = OpenBlog::Series.create!(name: "Learning gardens", slug: "learning-gardens", description: "A practical sequence.")
  end

  test "series orders public posts by position with unnumbered members last" do
    last = post("Last", position: nil)
    third = post("Third", position: 3)
    first = post("First", position: 1)
    post("Hidden", position: 2, status: "draft")
    post("Scheduled", position: 4, status: "scheduled")
    get "/blog/series/learning-gardens"
    assert_response :success
    assert_select "meta[name=robots][content='noindex, follow']"
    assert_select "h1", text: @series.name
    assert_select ".ob-list-description", text: @series.description
    assert_equal [ first.title, third.title, last.title ], Nokogiri::HTML(response.body).css(".ob-card-title").map(&:text).map(&:strip)
    refute_includes OpenBlog.sitemap_entries.map { |entry| entry[:loc] }, "https://example.test/blog/series/learning-gardens"
    get "/blog/series/absent"
    assert_response :not_found
    get "/blog/series/learning-gardens.json"
    assert_response :not_found
  end

  test "series navigation follows public sequence and changes immediately with membership" do
    first = post("First", position: 1)
    middle = post("Middle", position: 2)
    last = post("Last", position: nil)
    get middle.path
    assert_select ".ob-series-nav a[rel=prev][href='#{first.path}']"
    assert_select ".ob-series-nav a[rel=next][href='#{last.path}']"
    assert_select "[data-open-blog-content] .ob-series-nav", count: 0
    first.update!(status: "draft")
    get middle.path
    assert_select ".ob-series-nav a[rel=prev]", count: 0
    middle.update!(series: nil, series_position: nil)
    get middle.path
    assert_select ".ob-series-nav", count: 0
  end

  test "markdown has stored body FAQ notices and canonical headers without HTML layout" do
    record = post("Garden guide", position: 1)
    record.faqs.create!(question: "When to plant?", answer: "In spring.", position: 1)
    record.update!(canonical_url: "https://publisher.example/guide")
    get "#{record.path}.md"
    assert_response :success
    assert_equal "text/markdown", response.media_type
    assert_equal "noindex", response.headers["X-Robots-Tag"]
    assert_equal '<https://publisher.example/guide>; rel="canonical"', response.headers["Link"]
    assert response.body.start_with?("# Garden guide\n")
    assert_includes response.body, "## Body\n\nStored **Markdown**."
    assert_includes response.body, "## Frequently asked questions\n\n### When to plant?\n\nIn spring."
    assert response.body.end_with?("https://publisher.example/guide\n")
    refute_includes response.body, "<!DOCTYPE"
    record.update!(status: "draft")
    get "#{record.path}.md"
    assert_response :not_found
    get "/blog/garden.guide"
    assert_response :not_found
  end


  test "unnumbered neighbors are deterministic and pagination has distinct metadata" do
    numbered = post("Numbered", position: 5)
    first = post("Unnumbered first", position: nil)
    second = post("Unnumbered second", position: nil)
    assert_equal({ previous: numbered, next: second }, OpenBlog::ReaderQueries.series_neighbors(first))
    assert_equal({ previous: first, next: nil }, OpenBlog::ReaderQueries.series_neighbors(second))
    previous_size = OpenBlog.config.posts_per_page
    OpenBlog.config.posts_per_page = 1
    get "/blog/series/learning-gardens", params: { page: 2 }
    assert_response :success
    assert_select "title", text: /Learning gardens.*Page 2/
    assert_select "meta[name=description][content='Page 2 of the posts in Learning gardens — #{OpenBlog.config.site_name}.']"
    assert_select "link[rel=canonical][href$='?page=2']"
    get "/blog/series/learning-gardens", params: { page: 4 }
    assert_response :not_found
  ensure
    OpenBlog.config.posts_per_page = previous_size if previous_size
  end

  test "rich text markdown is plain text and missing format responses stay HTML" do
    formats = OpenBlog.config.body_formats
    OpenBlog.config.body_formats = %i[markdown rich_text]
    record = post("Rich garden", position: 1)
    record.update!(body_format: "rich_text", rich_body: "<p>A <strong>rich</strong> garden.</p>")
    get "#{record.path}.md"
    assert_response :success
    assert_includes response.body, "A rich garden."
    refute_includes response.body, "<strong>"
    assert_equal "<#{record.url}>; rel=\"canonical\"", response.headers["Link"]
    get record.path, headers: { "Accept" => "application/json" }
    assert_response :success
    assert_equal "text/html", response.media_type
    get "#{record.path}.json"
    assert_response :not_found
    OpenBlog::Redirect.create!(old_path: "/blog/gone-garden", source: "manual", occurred_on: Date.current)
    get "/blog/gone-garden.md"
    assert_response :gone
    assert_equal "text/html", response.media_type
    OpenBlog::Redirect.create!(old_path: "/blog/old-garden", new_path: record.path, source: "manual", occurred_on: Date.current)
    get "/blog/old-garden.md"
    assert_redirected_to record.path
  ensure
    OpenBlog.config.body_formats = formats
  end


  test "empty series has a real page and helper paths honor configured segments" do
    get "/blog/series/learning-gardens"
    assert_response :success
    assert_select ".ob-empty", count: 1
    routes = OpenBlog.config.route_segments
    OpenBlog.config.route_segments = routes.merge(series: "collections")
    assert_equal "/blog/collections/learning-gardens", OpenBlog::ReaderQueries.series_path(@series)
    view = ActionView::Base.empty
    [ OpenBlog::UrlHelper, OpenBlog::HeadHelper ].each { |helper| view.extend(helper) }
    html = Nokogiri::HTML.fragment(view.open_blog_head(@series))
    assert_equal "https://example.test/blog/collections/learning-gardens", html.at_css("link[rel=canonical]")["href"]
    assert_equal "noindex, follow", html.at_css("meta[name=robots]")["content"]
  ensure
    OpenBlog.config.route_segments = routes if routes
  end

  private

  def post(title, position:, status: "published")
    OpenBlog::Post.create!(title: title, slug: title.parameterize, body_markdown: "## Body\n\nStored **Markdown**.",
      author: @author, author_name: @author.name, series: @series, series_position: position, status: status)
  end
end
