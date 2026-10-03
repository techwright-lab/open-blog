require_relative "test_helper"

class ReaderHistoryTest < ActionDispatch::IntegrationTest
  ATOM = { "a" => "http://www.w3.org/2005/Atom" }.freeze

  setup do
    travel_to Time.utc(2026, 9, 20, 12)
    @saved_config = OpenBlog.config
    OpenBlog.instance_variable_set(:@config, @saved_config.deep_dup)
  end

  teardown do
    OpenBlog.instance_variable_set(:@config, @saved_config)
    travel_back
  end

  test "undated adoption stays undated across maintenance while Atom retains the adoption time" do
    adopted_at = 4.days.ago
    result = adopt("undated-note", now: adopted_at)
    assert result.success?, [ result.error&.message, result.error&.details ].inspect
    post = result.post
    assert_dates(post, published: nil, modified: nil, feed_updated: adopted_at)
    result = OpenBlog::Publish.call({ body: "Adjusted spacing.", change: "maintenance" }, post: post, actor: "Editor", now: 2.days.ago)
    assert result.success?, [ result.error&.message, result.error&.details ].inspect
    assert_dates(result.post, published: nil, modified: nil, feed_updated: adopted_at)
  end

  test "declared publication dates appear consistently without becoming evidence dates" do
    declared_at = Time.utc(2020, 4, 8, 10)
    result = adopt("declared-note", now: 4.days.ago, declaration: {
      declared_first_published_at: declared_at, reviewer_name: "Morgan", approved_at: declared_at,
      facts_checked: true, declared_by: "Publisher", declared_on: 4.days.ago.to_date
    })
    assert result.success?, [ result.error&.message, result.error&.details ].inspect
    assert_nil result.post.baseline.first_published_at
    assert_equal declared_at, result.post.baseline.declared_first_published_at
    assert_dates(result.post, published: declared_at, modified: declared_at, feed_updated: declared_at)
  end

  test "maintenance and metadata leave dates alone while substantive and correction releases advance them" do
    first_at = 5.days.ago
    result = OpenBlog::Publish.call({ title: "Changing seasons", slug: "changing-seasons", body: "Spring arrives." }, actor: "Editor", now: first_at)
    assert result.success?, [ result.error&.message, result.error&.details ].inspect
    post = result.post
    assert_dates(post, published: first_at, modified: first_at, feed_updated: first_at)
    [ [ "maintenance", 4.days.ago, first_at ], [ "substantive", 3.days.ago, 3.days.ago ], [ "correction", 2.days.ago, 2.days.ago ] ].each do |kind, at, expected|
      result = OpenBlog::Publish.call({ body: "Season note: #{kind}.", change: kind, note: "Updated the season note." }, post: post, actor: "Editor", now: at)
      assert result.success?, [ result.error&.message, result.error&.details ].inspect
      post = result.post
      assert_dates(post, published: first_at, modified: expected, feed_updated: expected)
    end
    post.update!(featured: true, category: OpenBlog::Category.create!(name: "Weather", slug: "weather"))
    post.tags << OpenBlog::Tag.create!(name: "Seasons", slug: "seasons")
    OpenBlog::Post.where(id: post.id).update_all(updated_at: 20.years.from_now)
    assert_dates(post.reload, published: first_at, modified: 2.days.ago, feed_updated: 2.days.ago)
    get post.path
    assert_select ".ob-correction", text: /Updated the season note/
  end

  test "full feeds preserve newest order limits category boundaries and sanitized bodies" do
    OpenBlog.config.feed_content = :full
    OpenBlog.config.feed_size = 2
    category = OpenBlog::Category.create!(name: "Planters", slug: "planters")
    posts = 3.times.map do |index|
      result = OpenBlog::Publish.call({ title: "Planter #{index}", slug: "planter-#{index}", category: category.slug,
        body: "## Planter #{index}\n\n**Water daily.**\n\n<script>alert(1)</script>" }, actor: "Editor", now: (5 - index).days.ago)
      assert result.success?, [ result.error&.message, result.error&.details ].inspect
      result.post
    end
    unrelated = OpenBlog::Publish.call({ title: "Elsewhere", slug: "elsewhere", body: "Other news." }, actor: "Editor", now: 1.day.ago)
    assert unrelated.success?, unrelated.error&.message
    get "/blog/feed.xml"
    assert_response :success
    xml = Nokogiri::XML(response.body) { |options| options.strict }
    assert_equal [ unrelated.post.url, posts.last.url ], xml.xpath("//a:entry/a:id", ATOM).map(&:text)
    get "/blog/category/planters/feed.xml"
    assert_response :success
    xml = Nokogiri::XML(response.body) { |options| options.strict }
    assert_equal posts.last(2).reverse.map(&:url), xml.xpath("//a:entry/a:id", ATOM).map(&:text)
    xml.xpath("//a:entry", ATOM).each do |entry|
      content = entry.at_xpath("a:content", ATOM)
      assert_equal "html", content["type"]
      html = Nokogiri::HTML5.fragment(content.text)
      assert_equal "Water daily.", html.at_css("strong").text
      assert_empty html.css("script")
      assert_nil entry.at_xpath("a:summary", ATOM)
    end
  end

  private

  def adopt(slug, now:, **attributes)
    OpenBlog::Adopt.call({ source_system: "reader-archive", source_id: slug, slug: slug, title: slug.humanize,
      body_format: "markdown", body: "A garden memory." }.merge(attributes), actor: "Archivist", now: now)
  end

  def assert_dates(post, published:, modified:, feed_updated:)
    get post.path
    assert_response :success
    html = Nokogiri::HTML5(response.body)
    graph = JSON.parse(html.at_css("script[type='application/ld+json']").text).fetch("@graph")
    schema = graph.find { |entry| entry["@type"] == "BlogPosting" }
    published ? assert_equal(published.iso8601, schema["datePublished"]) : assert_nil(schema["datePublished"])
    modified ? assert_equal(modified.iso8601, schema["dateModified"]) : assert_nil(schema["dateModified"])
    published_nodes = html.css("[data-open-blog-content] .ob-date--published time")
    if published
      assert published_nodes.any?
      assert_equal [ published.iso8601 ], published_nodes.map { |node| node["datetime"] }.uniq
    else
      assert_empty published_nodes
    end
    updated_nodes = html.css("[data-open-blog-content] .ob-date--updated time")
    if modified && (!published || modified > published)
      assert updated_nodes.any?
      assert_equal [ modified.iso8601 ], updated_nodes.map { |node| node["datetime"] }.uniq
    else
      assert_empty updated_nodes
    end
    entry = OpenBlog.sitemap_entries.find { |item| item[:loc] == post.url }
    assert entry
    modified ? assert_equal(modified, entry[:lastmod]) : assert_nil(entry[:lastmod])
    get "/blog/feed.xml"
    assert_response :success
    atom = Nokogiri::XML(response.body).xpath("//a:entry", ATOM).find { |item| item.at_xpath("a:id", ATOM).text == post.url }
    assert atom
    published ? assert_equal(published.iso8601, atom.at_xpath("a:published", ATOM)&.text) : assert_nil(atom.at_xpath("a:published", ATOM))
    assert_equal feed_updated.iso8601, atom.at_xpath("a:updated", ATOM).text
  end
end
