require_relative "test_helper"
require "minitest/mock"
require_relative "../lib/open_blog/surface_report/page_checks"

class SurfaceReportPagesTest < ActiveSupport::TestCase
  Page = Struct.new(:url, :status, :headers, :body, :document, :article, :articles, keyword_init: true)
  class Context
    attr_reader :posts, :config, :now, :results, :pages
    def initialize(posts)
      @posts, @config, @now, @results, @pages = posts, OpenBlog.config, Time.current, [], {}
    end
    def record(predicate, status, reason, post: nil, marks: [], details: nil)
      @results << { predicate: predicate, status: status, reason: reason, post_id: post&.id, marks: marks, details: details }
      @results.last
    end
    def absolute(path)
      URI.join(config.public_base_url, path).to_s if config.public_base_url && path
    end
    def page(url)
      pages[url] || Page.new(url: url, status: 0, headers: {}, body: "", document: Nokogiri::HTML5(""), articles: [])
    end
    def post_page(post)
      page(absolute(post.path))
    end
    def robots_allowed?(_url, _agent)
      true
    end
  end

  setup do
    @post = OpenBlog::Publish.call({ title: "Garden report", description: "A report on gardens.", body: "A garden." }, actor: "Editor").post
    @context = Context.new([ @post ])
    @settings = %i[policy_urls posts_per_page public_base_url].to_h { |key| [ key, OpenBlog.config.public_send(key) ] }
  end

  teardown { @settings.each { |key, value| OpenBlog.config.public_send("#{key}=", value) } }

  test "unavailable responses cannot produce successful page checks" do
    OpenBlog::SurfaceReport::PageChecks.new(@context).call
    page_rows = @context.results.select { |row| row[:post_id] == @post.id }
    assert_includes page_rows.map { |row| row[:predicate] }, "T15"
    assert page_rows.all? { |row| row[:status] == :not_verified }
  end

  test "malformed fetched markup fails concrete presence checks" do
    add_page(@post.url, '<html><head><title></title></head><body><h1>Wrong</h1><h3>Jump</h3><img src="a"></body></html>')
    OpenBlog::SurfaceReport::PageChecks.new(@context).call
    %w[E1 E3 T3 T7 T8 T9 T10 T11 T12 T13 T15 T16 T17].each do |predicate|
      assert_equal :fail, @context.results.find { |row| row[:predicate] == predicate && row[:post_id] == @post.id }[:status], predicate
    end
  end


  test "complete fetched evidence passes page and site checks" do
    install_valid_pages
    OpenBlog::SurfaceReport::PageChecks.new(@context).call
    assert @context.results.all? { |row| row[:status] == :pass }, @context.results.reject { |row| row[:status] == :pass }.inspect
    assert_equal 21, @context.results.length
  end

  test "policy response and visible link are both required without reading label policy" do
    install_valid_pages
    @context.pages[@context.absolute("/responsible")].status = 404
    OpenBlog::SurfaceReport::PageChecks.new(@context).call
    assert_equal :fail, result("E4")[:status]
    @context.results.clear
    @context.pages[@context.absolute("/responsible")].status = 200
    @context.post_page(@post).document.css("a[href='/responsible']").remove
    OpenBlog::SurfaceReport::PageChecks.new(@context).call
    assert_equal :fail, result("E4")[:status]
  end

  test "duplicate post metadata and missing newest feed entry fail" do
    install_valid_pages
    other = OpenBlog::Publish.call({ title: "Other garden", description: "Different garden", body: "Another garden" }, actor: "Editor").post
    @context.posts << other
    original = @context.post_page(@post)
    add_page(other.url, original.body, article: original.article)
    OpenBlog::SurfaceReport::PageChecks.new(@context).call
    assert_equal :fail, result("T7")[:status]
    assert_equal :fail, result("T8")[:status]
    assert_equal :fail, result("T6")[:status]
  end

  test "list pagination is fetched and duplicate indexable descriptions fail" do
    install_valid_pages
    OpenBlog.config.posts_per_page = 1
    OpenBlog::Publish.call({ title: "Second post", body: "Second body" }, actor: "Editor")
    add_page(@context.absolute("/blog?page=2"), list_html("Index page two", "Same index description", robots: "index, follow"))
    add_page(@context.absolute("/blog"), list_html("Index", "Same index description", robots: "index, follow"))
    add_page(@context.absolute("/blog/author/#{@post.author.slug}?page=2"), list_html("Author page two", "Author two", robots: "noindex, follow"))
    OpenBlog::SurfaceReport::PageChecks.new(@context).call
    assert_equal :fail, result("T21")[:status]
  end


  test "missing public origin produces no successful page observations" do
    OpenBlog.config.public_base_url = nil
    OpenBlog::SurfaceReport::PageChecks.new(@context).call
    assert @context.results.all? { |row| row[:status] == :not_verified }, @context.results.inspect
  end

  test "page policy evidence never reads label policy" do
    install_valid_pages
    OpenBlog::LabelPolicy.stub(:for, ->(*) { raise "Label policy is not report evidence" }) do
      OpenBlog::SurfaceReport::PageChecks.new(@context).call
    end
    assert_equal :pass, result("E4")[:status]
  end

  test "declared dates carry their mark while unknown adoption dates stay unverified" do
    published = 2.years.ago.change(usec: 0)
    input = { source_system: "archive", source_id: "declared", title: "Older garden", slug: "older-garden", body_format: "markdown", body: "Old notes.",
      declaration: { reviewer_name: "Reviewer", facts_checked: true, approved_at: published, declared_by: "Publisher", declared_on: Date.current.to_s, declared_first_published_at: published } }
    adopted = OpenBlog::Adopt.call(input, actor: "Importer")
    assert adopted.success?, adopted.error&.message
    @post = adopted.post
    @context = Context.new([ @post ])
    install_valid_pages
    OpenBlog::SurfaceReport::PageChecks.new(@context).call
    assert_equal :pass, result("E5")[:status]
    assert_equal [ "publisher declaration" ], result("E5")[:marks]
    unknown = OpenBlog::Adopt.call(input.except(:declaration).merge(source_id: "unknown", slug: "unknown-garden"), actor: "Importer")
    assert unknown.success?, unknown.error&.message
    @post = unknown.post
    @context = Context.new([ @post ])
    add_page(@post.url, "<html><body><h1>Older garden</h1></body></html>")
    OpenBlog::SurfaceReport::PageChecks.new(@context).call
    assert_equal :not_verified, result("E5")[:status]
    assert_equal :fail, result("T15")[:status]
  end


  test "a hidden author node is not visible author evidence" do
    install_valid_pages
    @context.post_page(@post).document.at_css(".ob-byline-author")["hidden"] = "hidden"
    OpenBlog::SurfaceReport::PageChecks.new(@context).call
    assert_equal :fail, result("E1")[:status]
    assert_equal :fail, result("E3")[:status]
    assert_equal :fail, result("T16")[:status]
  end


  test "valid JSON with nonobject feed shapes fails without raising" do
    install_valid_pages
    [ "[]", "42", "null", '"feed"', "true" ].each do |body|
      @context.results.clear
      add_page(@context.absolute("/blog/feed.json"), body)
      OpenBlog::SurfaceReport::PageChecks.new(@context).call
      assert_equal :fail, result("T6")[:status], body
    end
  end

  private

  def result(id)
    @context.results.find { |row| row[:predicate] == id }
  end

  def list_html(title, description, robots: "noindex, follow")
    "<html lang='en'><head><title>#{title}</title><meta name='description' content='#{description}'><meta name='robots' content='#{robots}'><link rel='alternate' type='application/feed+json' href='/blog/feed.json'></head><body><h1>#{title}</h1></body></html>"
  end

  def install_valid_pages
    published = @post.published_at.iso8601
    article = { "@type" => "BlogPosting", "headline" => @post.title, "author" => { "@type" => "Person", "name" => @post.author_name },
      "datePublished" => published, "dateModified" => published }
    body = "<html lang='en'><head><title>Garden report</title><meta name='description' content='A report on gardens.'><meta name='viewport' content='width=device-width, initial-scale=1'>" +
      "<link rel='canonical' href='#{@post.url}'><link rel='alternate' type='application/feed+json' href='/blog/feed.json'>" +
      %w[title type image url].map { |field| "<meta property='og:#{field}' content='value'>" }.join +
      "</head><body><h1>#{@post.title}</h1><a class='ob-byline-author' href='/blog/author/#{@post.author.slug}'>#{@post.author_name}</a>" +
      "<span class='ob-date--published'><span>Published</span><time datetime='#{published}'>Today</time></span><a href='/responsible'>Publisher</a><h2>Body</h2><p>A garden.</p></body></html>"
    add_page(@post.url, body, article: article)
    OpenBlog.config.policy_urls = { responsible_party: "/responsible", corrections: "/corrections", editorial: "/editorial", ai_use: "/ai" }
    OpenBlog.config.policy_urls.each_value { |path| add_page(@context.absolute(path), "<html><body>Policy</body></html>") }
    add_page(@context.absolute("/blog/author/#{@post.author.slug}"), list_html("The author", "The author's posts"))
    add_page(@context.absolute("/blog"), list_html("Blog index", "All posts", robots: "index, follow"))
    add_page(@context.absolute("/blog/sitemap.xml"), "<urlset xmlns='http://www.sitemaps.org/schemas/sitemap/0.9'><url><loc>#{@post.url}</loc><lastmod>#{published}</lastmod></url></urlset>")
    add_page(@context.absolute("/blog/feed.json"), { version: "https://jsonfeed.org/version/1.1", title: "Feed", items: [ { id: @post.url, content_text: "A garden." } ] }.to_json)
  end

  def add_page(url, body, status: 200, article: nil)
    @context.pages[url] = Page.new(url: url, status: status, headers: {}, body: body,
      document: Nokogiri::HTML5(body), article: article, articles: article ? [ article ] : [])
  end
end
