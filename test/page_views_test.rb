require_relative "test_helper"
require "minitest/mock"
require "rake"

class PageViewsTest < ActiveSupport::TestCase
  Request = Struct.new(:request_method, :user_agent, :headers, :format, keyword_init: true) do
    def get? = request_method == "GET"
  end

  setup do
    @post = OpenBlog::Publish.call({ title: "Counted trail" }, actor: "Editor").post
    @now = Time.utc(2026, 10, 6, 0, 15)
    @enabled = OpenBlog.config.page_views
    @retention = OpenBlog.config.page_view_retention_days
  end
  teardown do
    OpenBlog.config.page_views = @enabled
    OpenBlog.config.page_view_retention_days = @retention
  end

  test "counter uses one atomic statement and stores only a UTC daily total" do
    assert_equal %w[day id post_id views], OpenBlog::PageView.columns_hash.keys.sort
    statements = []
    observer = ->(_name, _start, _finish, _id, payload) { statements << payload[:sql] unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(observer, "sql.active_record") { OpenBlog::PageViews.count!(@post, browser, now: @now) }
    assert_equal 1, statements.grep(/INSERT INTO/i).size
    assert_equal 1, statements.grep(/\b(?:INSERT|UPDATE|DELETE|SELECT)\b/i).size
    OpenBlog::PageViews.count!(@post, browser, now: @now)
    assert_equal 2, OpenBlog::PageView.find_by!(post: @post, day: Date.new(2026, 10, 6)).views
    OpenBlog::PageViews.count!(@post, browser, now: @now - 1.hour)
    assert_equal 1, OpenBlog::PageView.find_by!(post: @post, day: Date.new(2026, 10, 5)).views
  end

  test "counter skips excluded requests and failures never escape" do
    [ browser(method: "HEAD"), browser(ua: "Googlebot"), browser(ua: nil), browser(headers: { "Sec-Purpose" => "prefetch" }), browser(format: Mime[:md]) ].each do |request|
      OpenBlog::PageViews.count!(@post, request, now: @now)
    end
    %w[facebookexternalhit WhatsApp ChatGPT-User Claude-User Perplexity-User anthropic-ai cohere-ai Google-InspectionTool].each do |ua|
      OpenBlog::PageViews.count!(@post, browser(ua: ua), now: @now)
    end
    OpenBlog.config.page_views = false
    OpenBlog::PageViews.count!(@post, browser, now: @now)
    assert_equal 0, OpenBlog::PageView.count
    OpenBlog.config.page_views = true
    OpenBlog::PageView.stub(:connection, -> { raise ActiveRecord::StatementInvalid, "Unavailable" }) do
      assert_nil OpenBlog::PageViews.count!(@post, browser, now: @now)
    end
  end

  test "daily reads are sparse inclusive and historical defaults use the requested end date" do
    [ [ 0, 2 ], [ -1, 3 ], [ -30, 7 ] ].each { |offset, views| OpenBlog::PageView.create!(post: @post, day: @now.to_date + offset, views: views) }
    result = OpenBlog::PageViews.for(@post, now: @now)
    assert_equal 5, result[:total]
    assert_equal @now.to_date - 29, result[:from]
    assert_equal [ @now.to_date - 1, @now.to_date ], result[:days].pluck(:day)
    result = OpenBlog::PageViews.for(@post, to: (@now.to_date - 1).iso8601, now: @now)
    assert_equal @now.to_date - 30, result[:from]
    assert_equal 10, result[:total]
    assert_raises(OpenBlog::Error::ValidationFailed) { OpenBlog::PageViews.for(@post, from: "2026-02-30", now: @now) }
    assert_raises(OpenBlog::Error::ValidationFailed) { OpenBlog::PageViews.for(@post, from: "2026-10-07", now: @now) }
  end

  test "top totals have deterministic order scope and bounded parameters" do
    draft = OpenBlog::SaveDraft.call({ title: "Draft statistics" }, actor: "Editor").post
    [ @post, draft ].each { |post| OpenBlog::PageView.create!(post: post, day: @now.to_date, views: 3) }
    result = OpenBlog::PageViews.top(days: 7, limit: 1, now: @now)
    assert_equal 7, result[:days]
    assert_equal [ @post.id ], result[:posts].pluck(:id)
    assert_equal %i[id slug title url views], result[:posts].first.keys
    assert_equal [ @post.id ], OpenBlog::PageViews.top(scope: OpenBlog::Post.listed, now: @now)[:posts].pluck(:id)
    [ { days: 0 }, { days: 36501 }, { limit: 101 } ].each do |input|
      assert_raises(OpenBlog::Error::ValidationFailed) { OpenBlog::PageViews.top(**input, now: @now) }
    end
  end

  test "retention is opt in and draft removal deletes its anonymous counters" do
    old = OpenBlog::PageView.create!(post: @post, day: @now.to_date - 31, views: 1)
    recent = OpenBlog::PageView.create!(post: @post, day: @now.to_date - 29, views: 1)
    assert_equal 0, OpenBlog::PageViews.prune!(now: @now)
    OpenBlog.config.page_view_retention_days = 30
    assert_equal 1, OpenBlog::PageViews.prune!(now: @now)
    refute OpenBlog::PageView.exists?(old.id)
    assert OpenBlog::PageView.exists?(recent.id)
    draft = OpenBlog::SaveDraft.call({ title: "Disposable draft" }, actor: "Editor").post
    OpenBlog::PageView.create!(post: draft, day: @now.to_date, views: 1)
    assert OpenBlog::Remove.call(draft, actor: "Editor").success?
    refute OpenBlog::PageView.exists?(post_id: draft.id)
  end

  test "prune task honors the cutoff and leaves retention disabled by default" do
    old = OpenBlog::PageView.create!(post: @post, day: @now.to_date - 31, views: 1)
    boundary = OpenBlog::PageView.create!(post: @post, day: @now.to_date - 30, views: 1)
    previous = Rake.application
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load OpenBlog::Engine.root.join("lib/tasks/open_blog.rake")
    travel_to @now do
      assert_output("Pruned 0 daily view totals\n") { Rake::Task["open_blog:prune_page_views"].invoke }
      OpenBlog.config.page_view_retention_days = 30
      Rake::Task["open_blog:prune_page_views"].reenable
      assert_output("Pruned 1 daily view totals\n") { Rake::Task["open_blog:prune_page_views"].invoke }
      refute OpenBlog::PageView.exists?(old.id)
      assert OpenBlog::PageView.exists?(boundary.id)
    end
  ensure
    Rake.application = previous
  end

  private

  def browser(method: "GET", ua: "Mozilla/5.0 Browser", headers: {}, format: Mime[:html])
    Request.new(request_method: method, user_agent: ua, headers: headers, format: format)
  end
end
