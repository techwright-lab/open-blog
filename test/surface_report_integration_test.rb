require_relative "test_helper"

class SurfaceReportIntegrationTest < ActiveSupport::TestCase
  class RackClient
    attr_reader :requests
    def initialize
      @requests = []
      @client = Rack::MockRequest.new(Rails.application)
    end
    def get(url, headers:)
      @requests << url
      @client.get(url, headers.transform_keys { |name| "HTTP_#{name.upcase.tr('-', '_')}" })
    end
  end

  setup do
    @cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @configuration = OpenBlog.config
    OpenBlog.instance_variable_set(:@config, @configuration.deep_dup)
    OpenBlog.config.public_base_url = "http://www.example.com"
    OpenBlog.config.policy_urls = {}
    OpenBlog::Page::KINDS.each do |kind|
      OpenBlog::Page.create!(kind: kind, title: "Publisher #{kind.humanize}", body_markdown: "Contact the garden editors.", status: "published")
    end
    @post = OpenBlog::Publish.call({ title: "Rivière notes", description: "A quiet riverside path.", body: "Watch the water.\n\n## Along the bank\n\nWalk slowly.",
      provenance: "ai_assisted", approval: { name: "Morgan", facts_checked: true },
      faq: [ { question: "Where to begin?", answer: "At the footbridge." } ] }, actor: "Editor").post
    @client = RackClient.new
    @http = OpenBlog::SurfaceReport::Http.new(client: @client)
  end
  teardown do
    OpenBlog.instance_variable_set(:@config, @configuration)
    Rails.cache = @cache
  end

  test "report compares records with actual Rack reader responses without adding views" do
    report = nil
    assert_no_difference [ "OpenBlog::PageView.count", "OpenBlog::Revision.count", "OpenBlog::Publication.count" ] do
      report = OpenBlog::SurfaceReport.run(scope: :post, post: @post, http: @http).to_h
    end
    %w[E1 E3 E4 E5 E6 E18 E19 T3 T5 T6 T7 T8 T15 T16].each do |id|
      row = report[:results].find { |item| item[:predicate] == id && (item[:post_id] == @post.id || item[:post_id].nil?) }
      assert_equal "pass", row&.fetch(:result), "#{id}: #{row.inspect}"
    end
    assert_includes @client.requests, @post.url
    assert_includes @client.requests, "http://www.example.com/blog/feed.xml"
    assert_equal @client.requests.uniq, @client.requests
  end

  test "missing policy and stored content drift are detected independently" do
    OpenBlog.config.policy_urls[:responsible_party] = "/missing-publisher"
    OpenBlog::Post.where(id: @post.id).update_all(body_markdown: "Unrecorded replacement.")
    report = OpenBlog::SurfaceReport.run(scope: :post, post: @post.reload, http: @http).to_h
    %w[E4 E19 E20].each do |id|
      row = report[:results].find { |item| item[:predicate] == id && item[:post_id] == @post.id }
      assert_equal "fail", row&.fetch(:result), "#{id}: #{row.inspect}"
    end
  end
end
