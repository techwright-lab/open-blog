require_relative "test_helper"
require "minitest/mock"

class ReaderHelpersTest < ActiveSupport::TestCase
  setup do
    @original = OpenBlog.config
    OpenBlog.instance_variable_set(:@config, OpenBlog::Configuration.new)
    OpenBlog.configure do |config|
      config.site_name = "Garden Journal"
      config.public_base_url = "https://journal.example"
      config.default_author = { name: "Alex Green", type: :person }
      config.publisher = { name: "Garden Publishing", url: "https://journal.example" }
    end
    @view = ActionView::Base.empty
    [ OpenBlog::UrlHelper, OpenBlog::HeadHelper, OpenBlog::StructuredDataHelper, OpenBlog::ContentHelper,
      OpenBlog::NoticesHelper, OpenBlog::DatesHelper, OpenBlog::PaginationHelper ].each { |helper| @view.extend(helper) }
    @post = OpenBlog::Publish.call({ title: "Growing trees", slug: "growing-trees", description: "Care for young trees.",
      body: "## Soil\n\nGood soil.\n\n### Water\n\nWater often.\n\n## Roots\n\nKeep roots moist." }, actor: "Editor", now: 2.days.ago).post
    context(:post, @post, path: @post.path)
  end

  teardown do
    OpenBlog.instance_variable_set(:@config, @original)
  end

  test "post head has one canonical metadata feeds and original absolute social image" do
    image = OpenBlog::Image.create!(sha256: "a" * 64, filename: "a leaf.png", content_type: "image/png", byte_size: 1, width: 30, height: 20)
    @post.social_image = image
    @post.search_title = "Tree care"
    @post.search_description = "Practical tree advice."
    doc = html(@view.open_blog_head)
    assert_equal 1, doc.css('link[rel="canonical"]').length
    assert_equal "https://journal.example/blog/growing-trees", doc.at_css('link[rel="canonical"]')["href"]
    assert_equal "Tree care — Garden Journal", doc.at_css("title").text
    assert_equal "Practical tree advice.", doc.at_css('meta[name="description"]')["content"]
    assert_equal "https://journal.example#{image.path}", doc.at_css('meta[property="og:image"]')["content"]
    assert_equal "article", doc.at_css('meta[property="og:type"]')["content"]
    assert_equal "summary_large_image", doc.at_css('meta[name="twitter:card"]')["content"]
    assert_equal 1, doc.css('link[type="application/atom+xml"]').length
    assert_empty doc.css('link[type="application/feed+json"]')
    assert doc.at_css('meta[name="viewport"]')
  end

  test "pagination metadata is distinct with the primary taxonomy indexable" do
    category = OpenBlog::Category.create!(name: "Soil", slug: "soil")
    context(:category, category, path: "/blog/category/soil", page: 2)
    doc = html(@view.open_blog_head)
    assert_equal "Soil — Page 2 — Garden Journal", doc.at_css("title").text
    assert_equal "https://journal.example/blog/category/soil?page=2", doc.at_css('link[rel="canonical"]')["href"]
    assert_equal "Page 2 of the posts about Soil — Garden Journal.", doc.at_css('meta[name="description"]')["content"]
    refute_includes doc.at_css('meta[name="robots"]')["content"], "noindex"
    OpenBlog.config.primary_list_type = :tags
    assert_equal "noindex, follow", html(@view.open_blog_head).at_css('meta[name="robots"]')["content"]
    context(:index, nil, path: "/blog", page: 1)
    assert_equal "The blog of Garden Journal.", html(@view.open_blog_head).at_css('meta[name="description"]')["content"]
  end

  test "JSON LD escapes script terminators and describes the post and breadcrumb exactly once" do
    previous_escape = ActiveSupport::JSON::Encoding.escape_html_entities_in_json
    ActiveSupport::JSON::Encoding.escape_html_entities_in_json = false
    @post.title = 'Trees </script><script>alert("bad")</script>'
    output = @view.open_blog_structured_data
    doc = html(output)
    assert_equal 1, doc.css("script").length
    graph = JSON.parse(doc.at_css("script").text).fetch("@graph")
    article = graph.select { |entry| entry["@type"] == "BlogPosting" }.sole
    assert_equal @post.title, article["headline"]
    assert_equal "Person", article.fetch("author")["@type"]
    assert_equal "https://journal.example/blog/author/alex-green", article.fetch("author")["url"]
    assert_equal @post.published_at.iso8601, article["datePublished"]
    assert_equal @post.modified_at.iso8601, article["dateModified"]
    assert_equal 1, graph.count { |entry| entry["@type"] == "BreadcrumbList" }
    refute graph.any? { |entry| entry["@type"] == "FAQPage" }
    assert output.html_safe?
  ensure
    ActiveSupport::JSON::Encoding.escape_html_entities_in_json = previous_escape
  end

  test "collection and organization profiles use their own structured data types" do
    category = OpenBlog::Category.create!(name: "Soil", slug: "soil")
    context(:category, category, path: "/blog/category/soil")
    data = JSON.parse(html(@view.open_blog_structured_data).at_css("script").text)["@graph"].first
    assert_equal "CollectionPage", data["@type"]
    assert_equal "ItemList", data["mainEntity"]["@type"]
    assert_equal @post.url, data["mainEntity"]["itemListElement"].sole["url"]
    author = @post.author
    author.author_type = "organization"
    context(:author, author, path: "/blog/author/#{author.slug}")
    data = JSON.parse(html(@view.open_blog_structured_data).at_css("script").text)["@graph"].first
    assert_equal "ProfilePage", data["@type"]
    assert_equal "Organization", data["mainEntity"]["@type"]
    assert_equal "noindex, follow", html(@view.open_blog_head).at_css('meta[name="robots"]')["content"]
    context(:index, nil, path: "/blog")
    data = JSON.parse(html(@view.open_blog_structured_data).at_css("script").text)["@graph"].first
    assert_equal "Blog", data["@type"]
  end

  test "valid modification without a publish date remains visible and future dates are omitted" do
    @post.published_at = nil
    @post.modified_at = 1.day.ago
    doc = html(@view.open_blog_byline(@post))
    assert_includes doc.text, "Updated"
    refute_includes doc.text, "Published"
    assert_equal @post.modified_at.iso8601, doc.at_css("time")["datetime"]
    data = JSON.parse(html(@view.open_blog_structured_data).at_css("script").text)["@graph"].first
    refute data.key?("datePublished")
    assert data.key?("dateModified")
    @post.modified_at = 1.day.from_now
    @post.stub(:updated_at, 10.years.from_now) do
      assert_empty html(@view.open_blog_byline(@post)).css("time")
      assert_empty html(@view.open_blog_head).css('meta[property^="article:"]')
    end
  end

  test "post helpers preserve original cover wrap body and link author and TOC" do
    @post.cover_image = OpenBlog::Image.new(sha256: "b" * 64, filename: "tree.png", content_type: "image/png", byte_size: 1, width: 60, height: 40)
    @post.cover_alt = "A young tree"
    cover = html(@view.open_blog_cover(@post)).at_css("figure > img")
    assert_equal @post.cover_image.path, cover["src"]
    assert_equal [ "60", "40", "A young tree" ], %w[width height alt].map { |key| cover[key] }
    assert_equal "Growing trees", html(@view.open_blog_title(@post)).at_css("h1").text
    assert html(@view.open_blog_post_content(@post) { "Contents" }).at_css("article[data-open-blog-content]")
    assert html(@view.open_blog_byline(@post)).at_css('a[href="/blog/author/alex-green"]')
    toc = html(@view.open_blog_toc(@post))
    assert_equal %w[#soil #water #roots], toc.css("a").map { |node| node["href"] }
    assert_equal [ "Soil", "Water", "Roots" ], toc.css("a").map(&:text)
    @post = OpenBlog::Publish.call({ body: "## Only one", change: "substantive" }, post: @post, actor: "Editor").post
    assert_equal "", @view.open_blog_toc(@post)
  end

  test "notices disclosures and corrections escape record text and select the latest declaration" do
    @post.connection_declarations.create!(declared_by: "Editor", declared_on: Date.yesterday,
      connections: [ { party: "Old", relation: "former employer" } ], third_party_paid: true)
    @post.connection_declarations.create!(declared_by: "Editor", declared_on: 3.days.ago.to_date,
      connections: [ { party: "<script>Tree Co</script>", relation: "supplier" } ], third_party_paid: true)
    notices = html(@view.open_blog_notices(@post))
    assert_includes notices.text, "The use of AI"
    assert_includes notices.text, "paid"
    disclosure = html(@view.open_blog_disclosure(@post))
    assert_includes disclosure.text, "Tree Co"
    refute_includes disclosure.text, "Old"
    assert_empty disclosure.css("script")
    @post.publications.create!(revision: @post.public_revision, entry_type: "correction", occurred_at: 1.hour.ago,
      note: "Fixed <script>typo</script>")
    correction = html(@view.open_blog_corrections(@post))
    assert_includes correction.text, "Correction"
    assert_includes correction.text, "Fixed <script>typo</script>"
    assert_empty correction.css("script")
  end

  test "pagination has current page semantics and page one has no query" do
    context(:index, nil, path: "/blog", page: 2, total_pages: 3)
    doc = html(@view.open_blog_paginate)
    assert doc.at_css("nav[aria-label]")
    assert_equal "2", doc.at_css('[aria-current="page"]').text
    assert doc.at_css('a[href="/blog"]')
    assert doc.at_css('a[href="/blog?page=3"]')
  end

  test "configured default social images resolve safely and unsafe schemes are omitted" do
    OpenBlog.config.default_social_image_url = "/images/social.png"
    assert_equal "https://journal.example/images/social.png", html(@view.open_blog_head).at_css('meta[property="og:image"]')["content"]
    OpenBlog.config.default_social_image_url = "javascript:alert(1)"
    assert_nil html(@view.open_blog_head).at_css('meta[property="og:image"]')
  end

  private

  def html(output)
    Nokogiri::HTML5.fragment(output)
  end

  def context(kind, record, path:, page: 1, total_pages: 1)
    pagination = Struct.new(:page, :total_pages, :records).new(page, total_pages, [ @post ].compact)
    value = OpenBlog::ReaderPage.new(kind: kind, record: record, pagination: pagination, path: path,
      breadcrumbs: [ { name: "Blog", path: "/blog" }, { name: record&.try(:name) || record&.try(:title), path: path } ].reject { |item| item[:name].nil? },
      base_url: "https://journal.example")
    @view.instance_variable_set(:@open_blog_page, value)
  end
end
