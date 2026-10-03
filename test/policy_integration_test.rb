require_relative "test_helper"
require "minitest/mock"
require "net/http"

class PolicyIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @settings = %i[policy_urls ai_label].to_h { |key| [ key, OpenBlog.config.public_send(key) ] }
    OpenBlog.config.policy_urls = {}
    OpenBlog.config.ai_label = :when_required
    result = OpenBlog::Publish.call({ title: "Pond observations", body: "Reeds shelter the pond.", provenance: "ai_assisted",
      approval: { name: "Avery", facts_checked: true } }, actor: "Editor")
    @post = result.post
    assert result.success?, result.error&.message
  end

  teardown { @settings.each { |key, value| OpenBlog.config.public_send("#{key}=", value) } }

  test "responsible page publication changes labels and findings without changing article history" do
    before = @post.attributes
    records = [ OpenBlog::Revision.count, OpenBlog::Publication.count, OpenBlog::Approval.count ]
    page = responsible_page(status: "draft")
    assert_equal :ai_assisted, OpenBlog::LabelPolicy.for(@post)
    assert_includes codes, :responsible_party_absent
    page.update!(status: "published")
    assert_equal :none, OpenBlog::LabelPolicy.for(@post)
    refute_includes codes, :responsible_party_absent
    assert_equal "none", OpenBlog::PostSerializer.call(@post)[:label]
    OpenBlog.config.ai_label = :always
    assert_equal :ai_assisted, OpenBlog::LabelPolicy.for(@post)
    OpenBlog.config.ai_label = :when_required
    page.update!(status: "draft")
    assert_equal :ai_assisted, OpenBlog::LabelPolicy.for(@post)
    assert_includes codes, :responsible_party_absent
    assert_equal before, @post.reload.attributes
    assert_equal records, [ OpenBlog::Revision.count, OpenBlog::Publication.count, OpenBlog::Approval.count ]
  end

  test "reader policy links and notices change despite a previous conditional request" do
    get @post.path
    assert_response :ok
    assert_select ".ob-notice--ai", count: 1
    assert_select "a.ob-responsible-party", count: 0
    previous_etag = response.headers["ETag"]
    page = responsible_page(status: "published")
    get @post.path, headers: { "If-None-Match" => previous_etag.to_s }
    assert_response :ok
    assert_select ".ob-notice--ai", count: 0
    assert_select "a.ob-responsible-party[href='#{page.path}']", count: 1
    page.update!(status: "draft")
    get @post.path, headers: { "If-None-Match" => response.headers["ETag"].to_s }
    assert_response :ok
    assert_select ".ob-notice--ai", count: 1
    assert_select "a.ob-responsible-party", count: 0
  end

  test "configured external responsibility is used without a render-time HTTP request" do
    responsible_page(status: "published")
    OpenBlog.config.policy_urls = { responsible_party: "https://publisher.example/about" }
    Net::HTTP.stub(:start, ->(*) { flunk "A label or reader request must not fetch a policy URL" }) do
      assert_equal :none, OpenBlog::LabelPolicy.for(@post)
      refute_includes codes, :responsible_party_absent
      get @post.path
      assert_response :ok
      assert_select "a.ob-responsible-party[href='https://publisher.example/about']", count: 1
    end
  end

  private

  def responsible_page(status:)
    OpenBlog::Page.create!(kind: "responsible_party", title: "Who edits these notes", body_markdown: "Avery edits these notes. Contact the editorial desk.",
      status: status, approved_by: "Avery", approved_on: Date.current)
  end

  def codes
    OpenBlog::Findings.for(@post).pluck(:code)
  end
end
