require_relative "../application_system_test_case"

class SurfaceReportBrowserTest < ApplicationSystemTestCase
  test "report fetches the same article served by the running host" do
    original = OpenBlog.config
    OpenBlog.instance_variable_set(:@config, original.deep_dup)
    OpenBlog.config.policy_urls = {}
    OpenBlog::Page.create!(kind: "responsible_party", title: "Our editors", body_markdown: "Contact the garden editors.", status: "published")
    post = OpenBlog::Publish.call({ title: "Riverbank journal", description: "An afternoon along the river.", body: "Look for the footbridge.",
      provenance: "ai_assisted", approval: { name: "Morgan", facts_checked: true }, faq: [ { question: "When?", answer: "After lunch." } ] }, actor: "Editor").post
    visit post.path
    assert_selector "h1", text: post.title
    OpenBlog.config.public_base_url = Capybara.current_session.server.base_url
    report = nil
    assert_no_difference "OpenBlog::PageView.sum(:views)" do
      report = OpenBlog::SurfaceReport.run(scope: :post, post: post).to_h
    end
    %w[E1 E3 E4 E18 E19 T3].each do |id|
      row = report[:results].find { |entry| entry[:predicate] == id && (entry[:post_id].nil? || entry[:post_id] == post.id) }
      assert_equal "pass", row&.fetch(:result), "#{id}: #{row.inspect}"
    end
  ensure
    OpenBlog.instance_variable_set(:@config, original) if original
  end
end
