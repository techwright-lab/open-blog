require_relative "test_helper"

class LabelPolicyTest < ActiveSupport::TestCase
  setup do
    @policy_urls = OpenBlog.config.policy_urls
    @ai_label = OpenBlog.config.ai_label
    OpenBlog.config.policy_urls = { responsible_party: "https://garden.example/about" }
  end

  teardown do
    OpenBlog.config.policy_urls = @policy_urls
    OpenBlog.config.ai_label = @ai_label
  end

  test "human authors need no AI notice under either policy" do
    post = published_post("human_written")
    OpenBlog.config.policy_urls = {}
    post.current_revision_identifier = "mismatched"
    %i[when_required always].each do |policy|
      OpenBlog.config.ai_label = policy
      assert_equal :none, OpenBlog::LabelPolicy.for(post)
    end
  end

  test "each approval kind satisfies reviewed AI and unknown provenance with complete evidence" do
    %w[ai_assisted unknown].each do |provenance|
      %w[sent imported declared].each do |kind|
        post = published_post(provenance)
        approve(post, kind: kind, facts_checked: true)
        OpenBlog.config.ai_label = :when_required
        assert_equal :none, OpenBlog::LabelPolicy.for(post), "#{provenance} #{kind} conditional"
        OpenBlog.config.ai_label = :always
        expected = provenance == "ai_assisted" ? :ai_assisted : :none
        assert_equal expected, OpenBlog::LabelPolicy.for(post), "#{provenance} #{kind} always"
      end
    end
  end

  test "missing review unchecked facts missing publisher and mismatched content keep the notice" do
    %w[ai_assisted unknown].each do |provenance|
      expected = provenance == "ai_assisted" ? :ai_assisted : :ai_unknown
      post = published_post(provenance)
      %i[when_required always].each do |policy|
        OpenBlog.config.ai_label = policy
        assert_equal expected, OpenBlog::LabelPolicy.for(post), "no approval #{provenance} #{policy}"
      end
      approve(post, facts_checked: false)
      %i[when_required always].each do |policy|
        OpenBlog.config.ai_label = policy
        assert_equal expected, OpenBlog::LabelPolicy.for(post), "unchecked #{provenance} #{policy}"
      end
      approve(post, facts_checked: true)
      OpenBlog.config.policy_urls = {}
      %i[when_required always].each do |policy|
        OpenBlog.config.ai_label = policy
        assert_equal expected, OpenBlog::LabelPolicy.for(post), "publisher absent #{provenance} #{policy}"
      end
      OpenBlog.config.policy_urls = { responsible_party: "https://garden.example/about" }
      post.current_revision_identifier = "different"
      %i[when_required always].each do |policy|
        OpenBlog.config.ai_label = policy
        assert_equal expected, OpenBlog::LabelPolicy.for(post), "content mismatch #{provenance} #{policy}"
      end
    end
  end

  test "an image without a content digest keeps the notice" do
    %w[ai_assisted unknown].each do |provenance|
      post = published_post(provenance)
      replace_revision(post, images: [ { "url" => "/media/leaf.png", "sha256" => "" } ])
      approve(post, facts_checked: true)
      %i[when_required always].each do |policy|
        OpenBlog.config.ai_label = policy
        assert_equal(provenance == "ai_assisted" ? :ai_assisted : :ai_unknown, OpenBlog::LabelPolicy.for(post))
      end
    end
  end

  test "all image digests and current revision approval are required" do
    post = published_post("unknown")
    approve(post, facts_checked: true)
    old_revision = post.public_revision
    replace_revision(post, images: [ { "url" => "/media/leaf.png", "sha256" => "d" * 64 } ])
    assert_equal :ai_unknown, OpenBlog::LabelPolicy.for(post)
    approve(post, facts_checked: true)
    assert_equal :none, OpenBlog::LabelPolicy.for(post)
    assert old_revision.approvals.exists?
  end

  test "draft and scheduled previews use approval for their current candidate" do
    %w[draft scheduled].each do |status|
      post = published_post("ai_assisted")
      approve(post, facts_checked: true)
      post.update_columns(status: status)
      candidate_payload = JSON.parse(post.public_revision.payload).merge("body" => "A new candidate #{status}.")
      identifier = Digest::SHA256.hexdigest(JSON.generate(candidate_payload))
      revision = post.revisions.create!(identifier: identifier, payload: JSON.generate(candidate_payload))
      post.update_columns(current_revision_identifier: identifier)
      OpenBlog.config.ai_label = :when_required
      assert_equal :ai_assisted, OpenBlog::LabelPolicy.for(post)
      approve(post, revision: revision, facts_checked: true)
      assert_equal :none, OpenBlog::LabelPolicy.for(post)
    end
  end

  test "missing revision and malformed image payload cannot suppress the notice" do
    post = OpenBlog::Post.new(provenance: "unknown")
    assert_equal :ai_unknown, OpenBlog::LabelPolicy.for(post)
    post = published_post("unknown")
    replace_revision(post, images: nil)
    approve(post, facts_checked: true)
    assert_equal :ai_unknown, OpenBlog::LabelPolicy.for(post)
  end

  private

  def published_post(provenance)
    author = OpenBlog::Author.find_or_create_by!(slug: "garden-writer") { |record| record.name = "Garden Writer" }
    OpenBlog::Post.create!(title: "Garden entry", slug: "garden-entry-#{OpenBlog::Post.count}",
      author: author, author_name: author.name, provenance: provenance, status: "published")
  end

  def approve(post, kind: "sent", facts_checked:, revision: post.public_revision)
    post.approvals.create!(revision: revision, kind: kind, facts_checked: facts_checked,
      reviewer_name: "Garden Reviewer", approved_at: Time.current,
      declared_on: Date.current, declared_by: "Garden Reviewer", confirmed_by: "Archivist", evidence: "Review record")
  end

  def replace_revision(post, images:)
    payload = JSON.parse(post.public_revision.payload).merge("images" => images)
    identifier = Digest::SHA256.hexdigest(JSON.generate(payload))
    revision = post.revisions.create!(identifier: identifier, payload: JSON.generate(payload))
    post.update_columns(public_revision_id: revision.id, current_revision_identifier: identifier)
    post.association(:public_revision).reset
  end
end
