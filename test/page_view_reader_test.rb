require_relative "test_helper"
require "minitest/mock"

class PageViewReaderTest < ActionDispatch::IntegrationTest
  BROWSER = { "User-Agent" => "Mozilla/5.0 ExampleBrowser" }.freeze

  setup do
    @settings = %i[page_views popular_posts].to_h { |key| [ key, OpenBlog.config.public_send(key) ] }
    OpenBlog.config.page_views = true
    OpenBlog.config.popular_posts = { enabled: false, days: 30, limit: 5 }
    @post = OpenBlog::Publish.call({ title: "Autumn orchard", body: "Watch the apples." }, actor: "Editor").post
  end
  teardown { @settings.each { |key, value| OpenBlog.config.public_send("#{key}=", value) } }

  test "HTML success and conditional responses count while other representations do not" do
    get @post.path, headers: BROWSER
    assert_response :ok
    assert_equal 1, views
    get @post.path, headers: BROWSER.merge("If-None-Match" => response.headers["ETag"])
    assert_response :not_modified
    assert_equal 2, views
    head @post.path, headers: BROWSER
    assert_response :ok
    get "#{@post.path}.md", headers: BROWSER
    assert_response :ok
    get "/blog/feed.json", headers: BROWSER
    assert_response :ok
    get "/blog/feed.xml", headers: BROWSER
    assert_response :ok
    assert_equal 2, views
  end

  test "bots missing agents prefetches and disabled counting leave no view rows" do
    [ {}, { "User-Agent" => "Googlebot" }, { "User-Agent" => "curl/9" }, BROWSER.merge("Sec-Purpose" => "prefetch;prerender") ].each do |headers|
      get @post.path, headers: headers
      assert_response :ok
    end
    OpenBlog.config.page_views = false
    get @post.path, headers: BROWSER
    assert_response :ok
    assert_equal 0, views
  end

  test "previews redirects missing pages and removed pages are not counted" do
    draft = OpenBlog::SaveDraft.call({ title: "Preview notes", body: "Unpublished." }, actor: "Editor").post
    get "/blog/preview/#{draft.preview_token}", headers: BROWSER
    assert_response :ok
    OpenBlog::Redirect.create!(old_path: "/blog/old-orchard", new_path: @post.path, source: "manual", occurred_on: Date.current)
    OpenBlog::Redirect.create!(old_path: "/blog/gone-orchard", source: "manual", occurred_on: Date.current)
    get "/blog/old-orchard", headers: BROWSER
    assert_response :moved_permanently
    get "/blog/missing-orchard", headers: BROWSER
    assert_response :not_found
    get "/blog/gone-orchard", headers: BROWSER
    assert_response :gone
    assert_equal 0, views
    assert_equal 0, OpenBlog::PageView.count
  end

  test "an unexpected counter failure never changes the reader response" do
    OpenBlog::PageViews.stub(:count!, ->(*) { raise "Counter unavailable" }) do
      get @post.path, headers: BROWSER
      assert_response :ok
      assert_select "h1", text: @post.title
    end
  end

  test "popular ranking is cached for one hour but withdrawn posts disappear immediately" do
    OpenBlog.config.popular_posts = { enabled: true, days: 30, limit: 2 }
    second = OpenBlog::Publish.call({ title: "Winter pruning", body: "Rest the trees." }, actor: "Editor").post
    third = OpenBlog::Publish.call({ title: "Spring planting", body: "Plant young trees." }, actor: "Editor").post
    draft = OpenBlog::SaveDraft.call({ title: "Private harvest plan" }, actor: "Editor").post
    day = Time.current.utc.to_date
    [ [ @post, 10 ], [ second, 5 ], [ draft, 100 ] ].each do |post, count|
      OpenBlog::PageView.create!(post: post, day: day, views: count)
    end
    Rails.stub(:cache, ActiveSupport::Cache::MemoryStore.new) do
      get "/blog"
      assert_equal [ @post.title, second.title ], popular_titles
      OpenBlog::PageView.create!(post: third, day: day, views: 50)
      get "/blog"
      assert_equal [ @post.title, second.title ], popular_titles
      OpenBlog::Unpublish.call(@post, actor: "Editor")
      get "/blog"
      assert_equal [ second.title ], popular_titles
      travel 61.minutes do
        get "/blog"
        assert_equal [ third.title, second.title ], popular_titles
      end
    end
  end

  private

  def views
    OpenBlog::PageView.where(post: @post).sum(:views)
  end

  def popular_titles
    Nokogiri::HTML(response.body).css(".ob-sidebar-popular a").map(&:text)
  end
end
