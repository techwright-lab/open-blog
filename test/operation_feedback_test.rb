require_relative "test_helper"

class OperationFeedbackTest < ActiveSupport::TestCase
  setup do
    @policies = OpenBlog.config.policy_urls.dup
    @label = OpenBlog.config.ai_label
  end

  teardown do
    OpenBlog.config.policy_urls = @policies
    OpenBlog.config.ai_label = @label
  end

  test "default publication returns nonblocking feedback" do
    result = OpenBlog::Publish.call({ title: "Compost notes", body: "Turn the pile." }, actor: "Editor")
    assert result.success?, result.error&.message
    assert_equal :ai_unknown, result.label
    codes = result.findings.pluck(:code).map(&:to_sym)
    %i[description_absent category_absent author_default_used provenance_unknown approval_absent connections_not_declared responsible_party_absent social_image_absent].each do |code|
      assert_includes codes, code
    end
    result.findings.each { |finding| assert finding.key?(:rule); assert finding[:message].present? }
  end

  test "approved AI content with responsible party clears label and incomplete approval is reported" do
    OpenBlog.config.policy_urls[:responsible_party] = "https://garden.example/about"
    result = OpenBlog::Publish.call({ title: "Compost notes", provenance: "ai_assisted", approval: { name: "Reviewer", facts_checked: true } }, actor: "Editor")
    assert result.success?
    assert_equal :none, result.label
    OpenBlog.config.ai_label = :always
    result = OpenBlog::Publish.call({}, post: result.post, actor: "Editor")
    assert_equal :ai_assisted, result.label
    result = OpenBlog::Publish.call({ title: "Mulch notes", provenance: "ai_assisted", approval: { name: "Reviewer", facts_checked: false } }, actor: "Editor")
    assert result.success?
    assert_equal :ai_assisted, result.label
    assert_includes result.findings.pluck(:code).map(&:to_sym), :approval_incomplete
  end

  test "slug and default author findings describe this write" do
    first = OpenBlog::Publish.call({ title: "Compost notes" }, actor: "Editor")
    result = OpenBlog::Publish.call({ slug: "compost-guide" }, post: first.post, actor: "Editor")
    assert result.success?
    codes = result.findings.pluck(:code).map(&:to_sym)
    assert_includes codes, :slug_changed
    refute_includes codes, :author_default_used
    again = OpenBlog::Publish.call({}, post: result.post, actor: "Editor")
    refute_includes again.findings.pluck(:code).map(&:to_sym), :slug_changed
  end

  test "late approval updates the returned label" do
    OpenBlog.config.policy_urls[:responsible_party] = "https://garden.example/about"
    post = OpenBlog::Publish.call({ title: "Compost notes", provenance: "ai_assisted" }, actor: "Editor").post
    result = OpenBlog::Approve.call(post, revision_identifier: post.public_revision.identifier, name: "Reviewer", facts_checked: true, actor: "Editor")
    assert result.success?
    assert_equal :none, result.label
    refute_includes result.findings.pluck(:code).map(&:to_sym), :approval_absent
  end
end
