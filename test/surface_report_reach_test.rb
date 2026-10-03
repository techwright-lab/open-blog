require_relative "test_helper"
require_relative "../lib/open_blog/surface_report/robots"
require_relative "../lib/open_blog/surface_report/reach_checks"

class SurfaceReportReachTest < ActiveSupport::TestCase
  Page = Struct.new(:url, :status, :headers, :body, keyword_init: true) do
    def document = Nokogiri::HTML5(body)
    def article = document.at_css("article")
  end
  class Context
    attr_accessor :reach, :posts, :config
    attr_reader :results, :pages, :requests
    def initialize
      @reach = true
      @posts = [ Struct.new(:id, :path).new(1, "/blog/trail") ]
      @config = Struct.new(:public_base_url, :sign_in_destinations).new("https://example.test", [])
      @results, @pages, @requests = [], {}, []
    end
    def absolute(path) = URI.join(config.public_base_url, path).to_s
    def post_page(post) = page(absolute(post.path))
    def page(url)
      requests << url
      pages.fetch(url) { Page.new(url: url, status: 0, headers: {}, body: "") }
    end
    def robots_allowed?(url, agent)
      robot = page("https://example.test/robots.txt")
      return nil if robot.status == 0 || robot.status >= 500
      return true if robot.status >= 400
      OpenBlog::SurfaceReport::Robots.allowed?(robot.body, URI(url).request_uri, agent)
    end
    def record(predicate, status, reason, post: nil, marks: [], details: nil)
      results << { predicate: predicate, result: status, reason: reason, details: details }
    end
  end

  setup do
    @context = Context.new
    add("https://example.test/blog/trail", body: '<article data-open-blog-content>Trail notes</article><footer><a href="/contact">Contact</a></footer>')
    add("https://example.test/robots.txt", body: "User-agent: *\nAllow: /\n")
    add("http://example.test/blog/trail", status: 301, headers: { "location" => "https://example.test/blog/trail" })
    add("https://example.test/contact")
  end

  test "disabled reach does not request pages and records all three checks as unverified" do
    @context.reach = false
    run_checks
    assert_equal %w[T1 T2 T14], @context.results.pluck(:predicate)
    assert_equal [ "not_verified" ], @context.results.pluck(:result).uniq
    assert_empty @context.requests
  end

  test "working crawler transport and full page links pass and one redirect is permitted" do
    add("https://example.test/contact", status: 302, headers: { "location" => "/contact-us" })
    add("https://example.test/contact-us")
    run_checks
    assert_equal [ "pass" ], @context.results.pluck(:result).uniq
    add("https://example.test/contact-us", status: 302, headers: { "location" => "/third" })
    @context.results.clear
    run_checks
    assert_equal "fail", result("T14")
    refute_includes @context.requests, "https://example.test/third"
  end

  test "crawler restrictions and missing HTTP upgrade fail independently" do
    add("https://example.test/robots.txt", body: "User-agent: bingbot\nDisallow: /blog\n")
    add("http://example.test/blog/trail")
    run_checks
    assert_equal "fail", result("T1")
    assert_equal "fail", result("T2")
    @context.results.clear
    add("https://example.test/robots.txt", status: 404)
    add("https://example.test/blog/trail", body: '<meta name="robots" content="noindex"><article data-open-blog-content>Trail</article>')
    run_checks
    assert_equal "fail", result("T1")
  end

  test "declared sign in destinations allow access gates and missing declarations remain unverified" do
    add("https://example.test/contact", status: 302, headers: { "location" => "/login" })
    add("https://example.test/login", body: '<form><input type="password"></form>')
    @context.config.sign_in_destinations = nil
    run_checks
    assert_equal "not_verified", result("T14")
    @context.results.clear
    @context.config.sign_in_destinations = []
    run_checks
    assert_equal "fail", result("T14")
    @context.results.clear
    @context.config.sign_in_destinations = [ "/contact" ]
    run_checks
    assert_equal "pass", result("T14")
  end

  test "header indexing directives are crawler scoped and body text is required" do
    add("https://example.test/blog/trail", body: "<article data-open-blog-content>Trail</article>", headers: { "x-robots-tag" => "SomeOtherBot: noindex" })
    run_checks
    assert_equal "pass", result("T1")
    @context.results.clear
    add("https://example.test/blog/trail", body: "<article data-open-blog-content>Trail</article>", headers: { "x-robots-tag" => "bingbot: noindex" })
    run_checks
    assert_equal "fail", result("T1")
    @context.results.clear
    add("https://example.test/blog/trail", body: "<article>Only a title</article><div data-open-blog-content> </div>")
    run_checks
    assert_equal "fail", result("T1")
  end

  test "external links are not fetched and unreachable local links stay unverified" do
    add("https://example.test/blog/trail", body: '<article data-open-blog-content>Trail</article><a href="https://outside.test/private">Outside</a><a href="/unreachable">Local</a>')
    run_checks
    assert_equal "not_verified", result("T14")
    refute_includes @context.requests, "https://outside.test/private"
    @context.results.clear
    add("https://example.test/unreachable", status: 404)
    run_checks
    assert_equal "fail", result("T14")
  end

  test "declared gates accept denied access while undeclared gates fail" do
    @context.config.sign_in_destinations = [ "/contact" ]
    add("https://example.test/contact", status: 403)
    run_checks
    assert_equal "pass", result("T14")
    @context.results.clear
    @context.config.sign_in_destinations = []
    run_checks
    assert_equal "fail", result("T14")
  end

  test "robots merges matching groups prefers specific rules and normalizes escaped unreserved octets" do
    body = "User-agent: *\nDisallow: /\nUser-agent: GOOGLEBOT\nDisallow: /blog/*\nAllow: /blog/trail$\nUser-agent: Googlebot\nDisallow: /private\nUser-agent: bingbot\nDisallow: /caf%C3%A9\n"
    robots = OpenBlog::SurfaceReport::Robots
    assert robots.allowed?("User-agent: Googlebot\nDisallow:\nUser-agent: bingbot\nDisallow: /private", "/private", "Googlebot")
    assert robots.allowed?(body, "/blog/%74rail", "Googlebot")
    refute robots.allowed?(body, "/blog/trail/extra", "Googlebot")
    refute robots.allowed?(body, "/private", "Googlebot")
    refute robots.allowed?(body, "/café", "bingbot")
    refute robots.allowed?("\uFEFFUser-agent: bingbot\rDisallow: /café\r".b, "/caf%C3%A9", "bingbot")
    assert robots.allowed?("User-agent: *\nDisallow: /x\nAllow: /x", "/x", "bingbot")
  end

  private

  def add(url, status: 200, headers: {}, body: "Available")
    @context.pages[url] = Page.new(url: url, status: status, headers: headers, body: body)
  end
  def run_checks = OpenBlog::SurfaceReport::ReachChecks.new(@context).call
  def result(predicate) = @context.results.find { |row| row[:predicate] == predicate }.fetch(:result)
end
