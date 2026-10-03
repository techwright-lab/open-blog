require_relative "test_helper"

class SurfaceReportTest < ActiveSupport::TestCase
  setup do
    @base = OpenBlog.config.public_base_url
    OpenBlog.config.public_base_url = nil
  end

  teardown { OpenBlog.config.public_base_url = @base }

  test "reports expose product metadata counts and explicit limits without private documents" do
    report = OpenBlog::SurfaceReport.run
    data = report.to_h
    assert_equal OpenBlog::VERSION, data[:gem_version]
    assert_equal "site", data[:scope]
    assert_equal "[data-open-blog-content]", data.dig(:declarations, :content_selector)
    assert_equal 4, data[:counts].length
    assert_equal data[:results].length, data[:counts].values.sum
    assert data[:results].any? { |row| row[:result] == "not verified" }
    assert_equal %w[T12_render T18 T19 T20], data[:not_run].map { |row| row[:predicate] }
    assert_equal %w[E2 E9 E10 E11 E12 E13 E14 E15 E23 E24 E25], data[:not_assessed]
    assert_includes report.to_text, data[:sentence]
    assert_includes report.to_text, JSON.generate(data[:declarations])
    refute_match(/conforms|_vault|STANDARD\.md|CONFORMANCE\.md/, JSON.generate(data))
    refute data.key?(:standard_version)
    refute data.key?(:conformance_version)
  end

  test "text retains detailed evidence from each result" do
    context = OpenBlog::SurfaceReport::Context.new(scope: :site, post: nil, page: 1, reach: false, http: Object.new)
    context.record("T14", :fail, "A destination did not open.", details: { url: "https://example.test/missing", status: 404 })
    report = OpenBlog::SurfaceReport::Result.new(context)
    assert_includes report.to_text, JSON.generate(report.to_h[:results].first[:details])
  end

  test "page parsing preserves UTF8 bytes and finds article objects in graphs" do
    page = OpenBlog::SurfaceReport::Page.new(url: "https://example.test", status: 200,
      body: '<html><head><title>Rivière</title><script type="application/ld+json">{"@graph":[{"@type":"BlogPosting","headline":"Rivière"}]}</script></head></html>'.b)
    assert_equal "Rivière", page.document.at_css("title").text
    assert_equal "Rivière", page.article["headline"]
  end

  test "all scope pages are bounded and explicit about uninspected articles" do
    author = OpenBlog::Author.create!(name: "Report inventory author")
    51.times { |number| OpenBlog::Post.create!(title: "Report row #{number}", slug: "report-row-#{number}", author: author, author_name: author.name, status: "draft") }
    OpenBlog::Post.where(author: author).update_all(status: "published")
    first = OpenBlog::SurfaceReport::Context.new(scope: :all, post: nil, page: 1, reach: false, http: Object.new)
    second = OpenBlog::SurfaceReport::Context.new(scope: :all, post: nil, page: 2, reach: false, http: Object.new)
    assert_equal 50, first.posts.length
    assert_equal 1, second.posts.length
    assert_equal 51, second.pagination[:total]
    assert_empty first.posts.map(&:id) & second.posts.map(&:id)
  end

  test "request budget returns uncertainty while preserving cached evidence" do
    OpenBlog.config.public_base_url = "https://example.test"
    requests = []
    client = Object.new
    client.define_singleton_method(:get) do |url|
      requests << url
      OpenBlog::SurfaceReport::Http::Response.new(status: 200, headers: {}, body: "small", url: url)
    end
    context = OpenBlog::SurfaceReport::Context.new(scope: :site, post: nil, page: 1, reach: false, http: client)
    500.times { |number| assert_equal 200, context.page("https://example.test/#{number}").status }
    assert_equal 0, context.page("https://example.test/extra").status
    assert_equal 200, context.page("https://example.test/0").status
    assert_equal 500, requests.length
    assert_match(/budget exhausted/, OpenBlog::SurfaceReport::Result.new(context).to_h[:limitations].first)
  end

  test "response byte budget stops retaining large resources" do
    calls = 0
    client = Object.new
    body = "x" * (9 * 1024 * 1024)
    client.define_singleton_method(:get) do |url|
      calls += 1
      OpenBlog::SurfaceReport::Http::Response.new(status: 200, headers: {}, body: body, url: url)
    end
    context = OpenBlog::SurfaceReport::Context.new(scope: :site, post: nil, page: 1, reach: false, http: client)
    3.times { |number| assert_equal 200, context.page("https://example.test/#{number}").status }
    assert_equal 0, context.page("https://example.test/large").status
    assert_equal 0, context.page("https://example.test/later").status
    assert_equal 4, calls
  end

  test "invalid scope post page and reach refuse before HTTP" do
    [ { scope: :missing }, { scope: :post }, { page: 0 }, { page: "1x" }, { reach: "yes" }, { post: "unused" } ].each do |options|
      assert_raises(OpenBlog::Error::ValidationFailed) { OpenBlog::SurfaceReport.run(**options) }
    end
  end

  test "post scope requires a listed record and missing base leaves page checks unverified" do
    draft = OpenBlog::SaveDraft.call({ title: "Report draft", body: "A private observation." }, actor: "Editor").post
    assert_raises(OpenBlog::Error::NotFound) { OpenBlog::SurfaceReport.run(scope: :post, post: draft.id) }
    published = OpenBlog::Publish.call({ title: "Report article", body: "A public observation." }, actor: "Editor").post
    report = OpenBlog::SurfaceReport.run(scope: :post, post: published.slug)
    assert_equal [ published.id ], report.to_h[:post_ids]
    %w[E1 E3 T3 T15 T1 T2 T14].each do |predicate|
      assert_equal "not verified", report.to_h[:results].find { |row| row[:predicate] == predicate }&.fetch(:result), predicate
    end
  end
end
