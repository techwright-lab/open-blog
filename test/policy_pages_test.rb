require_relative "test_helper"

class PolicyPagesTest < ActionDispatch::IntegrationTest
  setup do
    @policies = OpenBlog.config.policy_urls.dup
    OpenBlog.config.policy_urls = @policies.transform_values { nil }
  end

  teardown { OpenBlog.config.policy_urls = @policies }

  test "defaults stay stable and publication requires truthful content" do
    page = OpenBlog::Page.create!(kind: "editorial", title: "Editorial policy")
    assert_equal "editorial-policy", page.slug
    assert_equal "", page.body_markdown
    assert page.draft?
    assert_nil page.approved_by
    assert_nil page.approved_on
    page.update!(title: "Our editing process")
    assert_equal "editorial-policy", page.slug
    refute page.update(status: "published")
    page.assign_attributes(status: "draft", slug: "our-process")
    assert page.save
    %w[../escape slash/path bad%20slug dotted.slug].each do |slug|
      page.slug = slug
      refute page.valid?, slug
    end
    page.slug = "our-process"
    page.status = "invented"
    refute page.valid?
  end

  test "published pages render sanitized content and page metadata without post records" do
    page = OpenBlog::Page.create!(kind: "responsible_party", title: "Accountability <team>", status: "published",
      body_markdown: "## Contact us\n\nWrite to **our team**.\n\n<script>alert(1)</script>")
    get page.path
    assert_response :success
    assert_select "h1", text: "Accountability <team>"
    assert_select "h2[id]", text: /Contact us/
    assert_select ".ob-prose strong", text: "our team"
    assert_select "script:not([type='application/ld+json'])", text: /alert/, count: 0
    assert_select "link[rel=canonical][href='#{page.url}']"
    assert_select "meta[name=robots][content='index, follow']"
    assert_select "meta[property='article:published_time']", count: 0
    graph = Nokogiri::HTML(response.body).css("script[type='application/ld+json']").flat_map { |node| JSON.parse(node.text).fetch("@graph") }
    assert_includes graph.map { |entry| entry["@type"] }, "WebPage"
    refute_includes graph.map { |entry| entry["@type"] }, "BlogPosting"
    assert_equal page.path, OpenBlog.policy_url("responsible_party")
    assert_nil OpenBlog.policy_url(:unknown)
  end

  test "publication and overrides immediately control reader footer and sitemap" do
    page = OpenBlog::Page.create!(kind: "corrections", title: "Corrections", body_markdown: "Contact our editor.")
    get page.path
    assert_response :not_found
    assert_nil OpenBlog.policy_url(:corrections)
    page.update!(status: "published")
    get "/blog"
    assert_select "footer a[href='#{page.path}']", count: 1
    assert_includes OpenBlog.sitemap_entries.map { |entry| entry[:loc] }, page.url
    OpenBlog.config.policy_urls[:corrections] = "https://example.org/corrections"
    assert_equal "https://example.org/corrections", OpenBlog.policy_url(:corrections)
    get page.path
    assert_response :not_found
    get "/blog"
    assert_select "footer a[href='https://example.org/corrections']", count: 1
    refute_includes OpenBlog.sitemap_entries.map { |entry| entry[:loc] }, page.url
    OpenBlog.config.policy_urls[:corrections] = nil
    page.update!(status: "draft")
    get "/blog"
    assert_select "footer a[href='#{page.path}']", count: 0
    refute_includes OpenBlog.sitemap_entries.map { |entry| entry[:loc] }, page.url
  end

  test "custom slugs and strict HTML routes do not expose obsolete or alternate paths" do
    page = OpenBlog::Page.create!(kind: "ai_use", title: "AI use", body_markdown: "Our process.", status: "published")
    assert_equal "ai-use", page.slug
    old_path = page.path
    page.update!(slug: "our-ai-process")
    get old_path
    assert_response :not_found
    get "#{page.path}.json"
    assert_response :not_found
    get page.path, params: { format: "json" }
    assert_response :not_found
    writes = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      writes << payload[:sql] if payload[:sql].match?(/\A\s*(INSERT|UPDATE|DELETE)/i)
    end
    begin
      get page.path
      assert_response :success
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
    assert_empty writes
    assert_equal page.path, OpenBlog.policy_url(:ai_use)
  end

  test "direct page helpers and custom config preserve the local canonical path" do
    page = OpenBlog::Page.create!(kind: "editorial", title: "Editorial choices", body_markdown: "Our process.", status: "published")
    view = ActionView::Base.empty
    [ OpenBlog::UrlHelper, OpenBlog::HeadHelper, OpenBlog::StructuredDataHelper ].each { |helper| view.extend(helper) }
    document = Nokogiri::HTML.fragment(view.open_blog_head(page))
    assert_equal "#{page.title}#{OpenBlog.config.title_suffix}", document.at_css("title").text
    assert_equal page.url, document.at_css("link[rel=canonical]")["href"]
    assert_equal "website", document.at_css("meta[property='og:type']")["content"]
    graph = JSON.parse(Nokogiri::HTML.fragment(view.open_blog_structured_data(page)).at_css("script").text).fetch("@graph")
    assert_equal "WebPage", graph.first["@type"]
    assert_equal page.url, graph.last.fetch("itemListElement").last["item"]
    custom = OpenBlog::Configuration.new
    custom.policy_urls[:editorial] = "https://publisher.example/editorial"
    assert_equal "https://publisher.example/editorial", OpenBlog.policy_url(:editorial, config: custom)
    assert_equal page.path, OpenBlog.policy_url(:editorial)
  end

  test "all four policy kinds have stable routes and standalone metadata" do
    view = ActionView::Base.empty
    [ OpenBlog::UrlHelper, OpenBlog::HeadHelper ].each { |helper| view.extend(helper) }
    { "responsible_party" => "responsible-party", "corrections" => "corrections",
      "editorial" => "editorial-policy", "ai_use" => "ai-use" }.each do |kind, slug|
      page = OpenBlog::Page.create!(kind: kind, title: "Policy #{kind}", body_markdown: "The publisher's process.", status: "published")
      assert_equal slug, page.slug
      assert_equal "/blog/policies/#{slug}", page.path
      get page.path
      assert_response :success
      assert_select "footer a[href='#{page.path}']", count: 1
      metadata = Nokogiri::HTML.fragment(view.open_blog_head(page))
      assert_equal page.url, metadata.at_css("link[rel=canonical]")["href"]
      assert_equal "#{page.title}#{OpenBlog.config.title_suffix}", metadata.at_css("title").text
    end
  end
end
