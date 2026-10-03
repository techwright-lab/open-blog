require_relative "test_helper"

class OperationConsistencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @author = OpenBlog::Author.create!(name: "Robin Field", slug: "robin-#{SecureRandom.hex(6)}")
    @now = Time.utc(2026, 7, 12, 8)
    @hook = OpenBlog.config.before_publish
    @formats = OpenBlog.config.body_formats
  end

  teardown do
    OpenBlog.config.before_publish = @hook
    OpenBlog.config.body_formats = @formats
    ids = OpenBlog::Post.where(author: @author).pluck(:id)
    OpenBlog::Post.where(id: ids).update_all(public_revision_id: nil)
    [ OpenBlog::Approval, OpenBlog::Publication, OpenBlog::Baseline, OpenBlog::ConnectionDeclaration,
      OpenBlog::Revision, OpenBlog::Faq, OpenBlog::Tagging, OpenBlog::Redirect ].each do |model|
      model.where(post_id: ids).delete_all
    end
    ActionText::RichText.where(record_type: "OpenBlog::Post", record_id: ids).delete_all
    OpenBlog::Post.where(id: ids).delete_all
    @author.destroy!
  end

  test "republishing restores this posts historical aliases" do
    post = publish.post
    original_path = post.path
    moved = publish({ slug: "orchard-second" }, post: post)
    assert OpenBlog::Unpublish.call(moved.post, actor: "editor", now: @now).success?
    result = publish({}, post: moved.post)
    assert result.success?, result.error&.message
    assert_nil OpenBlog::Redirect.find_by(old_path: moved.post.path)
    assert_equal moved.post.path, OpenBlog::Redirect.find_by!(old_path: original_path).new_path
  end

  test "approval remains bound to content if the host hook changes it" do
    post = draft
    original = post.current_revision_identifier
    OpenBlog.config.before_publish = ->(candidate, _context) { candidate.title = "Changed by host"; nil }
    assert_no_difference [ "OpenBlog::Revision.count", "OpenBlog::Approval.count", "OpenBlog::Publication.count" ] do
      result = publish({ approval: { name: "Reviewer", facts_checked: true, revision_identifier: original } }, post: post)
      refute result.success?
      assert_equal :revision_mismatch, result.error.code
    end
    assert_equal "Orchard notes", post.reload.title
    assert post.draft?
  end

  test "host hook content changes still require an explicit change type" do
    post = publish.post
    OpenBlog.config.before_publish = ->(candidate, _context) { candidate.body_markdown = "Host replacement"; nil }
    assert_no_difference [ "OpenBlog::Revision.count", "OpenBlog::Publication.count" ] do
      result = publish({}, post: post)
      refute result.success?
      assert_equal :change_type_required, result.error.code
    end
    assert_equal "Water young trees.", post.reload.body_markdown
  end

  test "adopted posts require a change type even without a first publication" do
    post = draft
    revision = post.revisions.create!(identifier: post.current_revision_identifier,
      payload: OpenBlog::RevisionPayload.new(post).to_json)
    post.publications.create!(revision: revision, entry_type: "adopted", occurred_at: @now)
    post.create_baseline!(adopted_revision: revision, adopted_at: @now, provenance: "unknown")
    post.update_columns(status: "published", public_revision_id: revision.id)
    assert_no_difference [ "OpenBlog::Revision.count", "OpenBlog::Publication.count" ] do
      result = publish({ body: "A different recommendation" }, post: post)
      refute result.success?
      assert_equal :change_type_required, result.error.code
    end
    assert_equal "Water young trees.", post.reload.body_markdown
  end

  test "rich text approval matches the canonical body persisted in the same save" do
    OpenBlog.config.body_formats = [ :markdown, :rich_text ]
    post = draft(body_format: "rich_text", body_markdown: nil)
    post.rich_body = "<p class='tip'>Drain well<br/>Then rest.</p>"
    expected = OpenBlog::RevisionPayload.new(post).identifier
    result = publish({ body: "<p class='tip'>Drain well<br/>Then rest.</p>",
      approval: { name: "Reviewer", facts_checked: true, revision_identifier: expected } }, post: post)
    assert result.success?, result.error&.message
    stored = result.post.reload
    assert_equal expected, stored.current_revision_identifier
    assert_equal expected, OpenBlog::RevisionPayload.new(stored).identifier
    assert_equal expected, stored.approvals.sole.revision.identifier
    assert_equal expected, stored.public_revision.identifier
  end

  test "concurrent partial publications serialize against fresh persisted content" do
    skip "Row locking is specific to PostgreSQL" unless OpenBlog::Post.connection.adapter_name == "PostgreSQL"
    post = publish.post
    results = race do |index|
      attributes = index.zero? ? { title: "Summer pruning" } : { body: "Use clean tools." }
      publish(attributes.merge(change: "substantive"), post: OpenBlog::Post.find(post.id))
    end
    results.each { |result| assert result.success?, result.error&.message }
    stored = post.reload
    assert_equal "Summer pruning", stored.title
    assert_equal "Use clean tools.", stored.body_markdown
    assert_equal OpenBlog::RevisionPayload.new(stored).identifier, stored.public_revision.identifier
    assert_equal 3, stored.publications.count
    assert_equal 1, stored.publications.where(entry_type: "first").count
  end

  test "simultaneous first publications create one first entry" do
    skip "Row locking is specific to PostgreSQL" unless OpenBlog::Post.connection.adapter_name == "PostgreSQL"
    post = draft
    results = race { publish({}, post: OpenBlog::Post.find(post.id)) }
    results.each { |result| assert result.success?, result.error&.message }
    assert_equal 1, post.publications.count
    assert_equal "first", post.publications.sole.entry_type
    assert_equal 1, post.revisions.count
  end

  test "an approval racing an update never certifies the replacement content" do
    skip "Row locking is specific to PostgreSQL" unless OpenBlog::Post.connection.adapter_name == "PostgreSQL"
    post = publish.post
    original = post.public_revision.identifier
    updated, approval = race do |index|
      if index.zero?
        publish({ body: "Wait until the ground dries.", change: "substantive" }, post: post)
      else
        OpenBlog::Approve.call(post, revision_identifier: original, name: "Reviewer",
          facts_checked: true, actor: "editor", now: @now)
      end
    end
    assert updated.success?, updated.error&.message
    if approval.success?
      assert_equal original, post.approvals.sole.revision.identifier
    else
      assert_equal :revision_mismatch, approval.error.code
      assert_empty post.approvals
    end
    refute_equal original, post.reload.public_revision.identifier
    assert_empty post.approvals.where(revision: post.public_revision)
  end

  test "concurrent creation of one external identity stores one post and one first entry" do
    skip "Row locking is specific to PostgreSQL" unless OpenBlog::Post.connection.adapter_name == "PostgreSQL"
    results = race { publish(external_id: "orchard-source") }
    assert results.any?(&:success?)
    results.reject(&:success?).each { |result| assert_equal :identity_conflict, result.error.code }
    posts = OpenBlog::Post.where(external_id: "orchard-source")
    assert_equal 1, posts.count
    assert_equal 1, posts.sole.publications.where(entry_type: "first").count
    assert_equal 1, posts.sole.revisions.count
  end

  private

  def draft(**attributes)
    OpenBlog::Post.create!({ title: "Orchard notes", slug: "orchard-notes", body_markdown: "Water young trees.",
      author: @author, author_name: @author.name }.merge(attributes))
  end

  def publish(attributes = {}, post: nil, **keywords)
    input = post ? attributes.merge(keywords) : { title: "Orchard notes", slug: "orchard-notes",
      body: "Water young trees.", author: @author.id }.merge(attributes).merge(keywords)
    OpenBlog::Publish.call(input, post: post, actor: "editor", now: @now)
  end

  def race
    ready, start = Queue.new, Queue.new
    threads = 2.times.map do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          yield index
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    threads.map(&:value)
  end
end
