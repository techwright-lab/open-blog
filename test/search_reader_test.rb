require_relative "test_helper"

class SearchReaderTest < ActionDispatch::IntegrationTest
  setup do
    @settings = %i[search_rate_limit rate_limit_store posts_per_page].to_h { |key| [ key, OpenBlog.config.public_send(key) ] }
    OpenBlog.config.rate_limit_store = ActiveSupport::Cache::MemoryStore.new
    OpenBlog.config.search_rate_limit = { to: 30, within: 1.minute }
    @post = OpenBlog::Publish.call({ title: "Orchard notes", body: "Plant apple trees.", description: "Growing fruit." }, actor: "Editor").post
  end

  teardown { @settings.each { |key, value| OpenBlog.config.public_send("#{key}=", value) } }

  test "reader search returns public cards and bounded JSON suggestions" do
    9.times { |index| OpenBlog::Publish.call({ title: "Orchard season #{index}", body: "Apple trees." }, actor: "Editor") }
    OpenBlog::SaveDraft.call({ title: "Orchard private notes" }, actor: "Editor")
    get "/blog/search", params: { q: "orchard" }
    assert_response :ok
    assert_select "meta[name=robots][content='noindex, follow']"
    assert_select ".ob-post-card", count: 10
    assert_select ".ob-post-card", text: /private notes/, count: 0
    assert_select "form[role=search][method=get][action='/blog/search'] input[name=q][value=orchard]"
    get "/blog/search.json", params: { q: "orchard" }
    assert_response :ok
    assert_equal "application/json", response.media_type
    assert_equal 8, response.parsed_body.size
    assert_equal %w[description title url], response.parsed_body.first.keys.sort
    assert response.parsed_body.all? { |item| item["url"].start_with?("https://example.test/blog/") }
    assert_equal "noindex", response.headers["X-Robots-Tag"]
  end

  test "invalid queries are empty and search pagination preserves the escaped query" do
    [ nil, "a", "x" * 101, [ "orchard" ] ].each do |query|
      get "/blog/search.json", params: { q: query }
      assert_response :ok
      assert_equal [], response.parsed_body
    end
    OpenBlog::Publish.call({ title: "Orchard notes again", body: "More fruit." }, actor: "Editor")
    OpenBlog.config.posts_per_page = 1
    get "/blog/search", params: { q: "orchard notes" }
    assert_response :ok
    link = Nokogiri::HTML(response.body).at_css("a.ob-pagination-link")
    assert link
    assert_equal({ "q" => "orchard notes", "page" => "2" }, Rack::Utils.parse_nested_query(URI.parse(link["href"]).query))
    get link["href"]
    assert_response :ok
    assert_select ".ob-post-card", count: 1
    assert_select "input[name=q][value='orchard notes']"
  end

  test "cached sidebars never reuse another search query" do
    previous_store = OpenBlog::SearchController.cache_store
    previous_caching = OpenBlog::SearchController.perform_caching
    OpenBlog::SearchController.cache_store = ActiveSupport::Cache::MemoryStore.new
    OpenBlog::SearchController.perform_caching = true
    %w[orchard apple].each do |query|
      get "/blog/search", params: { q: query }
      assert_response :ok
      assert_select "input[name=q][value='#{query}']"
    end
  ensure
    OpenBlog::SearchController.cache_store = previous_store
    OpenBlog::SearchController.perform_caching = previous_caching
  end

  test "HTML and JSON share the configured address quota" do
    30.times do |index|
      get(index.even? ? "/blog/search" : "/blog/search.json", params: { q: "orchard" }, headers: { "REMOTE_ADDR" => "198.51.100.8" })
      assert_response :ok
    end
    get "/blog/search.json", params: { q: "orchard" }, headers: { "REMOTE_ADDR" => "198.51.100.8" }
    assert_response :too_many_requests
    get "/blog/search.json", params: { q: "orchard" }, headers: { "REMOTE_ADDR" => "198.51.100.9" }
    assert_response :ok
  end
end
