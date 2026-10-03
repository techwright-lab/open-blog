require_relative "test_helper"

class PublishingOperationsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @now = Time.utc(2026, 4, 5, 12)
    @approval_gate = OpenBlog.config.require_approval
    @hook = OpenBlog.config.before_publish
    clear_enqueued_jobs
  end

  teardown do
    OpenBlog.config.require_approval = @approval_gate
    OpenBlog.config.before_publish = @hook
    clear_enqueued_jobs
  end

  test "default publication creates one public revision and dates" do
    result = publish
    assert result.success?, result.error&.message
    assert result.created
    assert_equal({ revision: "new", publication: "first", approval: nil }, result.records)
    assert_equal @now, result.post.published_at
    assert_equal @now, result.post.modified_at
    assert_equal result.post.current_revision_identifier, result.post.public_revision.identifier
    assert_equal "Editor", result.post.public_revision.actor
    assert_equal "Editor", result.post.publications.first.released_by
    assert_equal :ai_unknown, result.label
    assert_empty result.findings
    again = publish({}, post: result.post)
    assert again.success?
    assert_equal 1, result.post.publications.count
    assert_equal 1, result.post.revisions.count
  end

  test "drafts have no release records and cannot overwrite public content" do
    draft = OpenBlog::SaveDraft.call(content, actor: "Editor")
    assert draft.success?, draft.error&.message
    assert draft.post.draft?
    assert_empty draft.post.revisions
    published = publish({}, post: draft.post)
    assert_refusal(:post_is_public) { OpenBlog::SaveDraft.call({ title: "Rejected" }, post: published.post, actor: "Editor") }
    assert_equal "Growing beans", published.post.reload.title
  end

  test "changed public content needs a change type and correction needs a note" do
    post = publish.post
    assert_refusal(:change_type_required) { publish({ body: "Different" }, post: post) }
    assert_refusal(:correction_note_required) { publish({ body: "Different", change: "correction" }, post: post) }
    assert_equal "Plant in spring.", post.reload.body_markdown
    assert_equal 1, post.publications.count
  end

  test "change types control editorial dates and reuse unchanged revisions" do
    post = publish.post
    later = @now + 1.day
    maintenance = publish({ body: "Plant after frost.", change: "maintenance" }, post: post, now: later)
    assert maintenance.success?, maintenance.error&.message
    assert_equal @now, maintenance.post.modified_at
    correction = publish({ body: "Plant after the last frost.", change: "correction", note: "Clarified timing" }, post: post, now: later)
    assert correction.success?
    assert_equal later, correction.post.modified_at
    assert_equal "Clarified timing", correction.post.publications.order(:id).last.note
    substantive = publish({ change: "substantive" }, post: post, now: later + 1.hour)
    assert substantive.success?
    assert_equal "same", substantive.records[:revision]
    assert_equal "substantive", substantive.records[:publication]
    assert_equal later + 1.hour, substantive.post.modified_at
    assert_equal @now, substantive.post.published_at
  end

  test "metadata changes do not create release records" do
    post = publish.post
    result = publish({ category: "Vegetables", tags: [ "Seasonal" ], series: "Garden year", series_position: 1, featured: true }, post: post, now: @now + 1.day)
    assert result.success?, result.error&.message
    assert_nil result.records[:publication]
    assert_equal @now, result.post.modified_at
    assert_equal 1, result.post.publications.count
  end

  test "approval false is stored but malformed approvals roll back all content" do
    result = publish(approval: { name: "Reviewer", facts_checked: false })
    assert result.success?, result.error&.message
    assert_equal false, result.post.approvals.first.facts_checked
    assert_equal "sent", result.records[:approval]
    [ { name: "Reviewer" }, { facts_checked: true }, { name: "Reviewer", facts_checked: "true" } ].each do |approval|
      assert_refusal(:approval_incomplete) { publish({ slug: "another", category: "Uncommitted", approval: approval }) }
    end
    refute OpenBlog::Category.exists?(name: "Uncommitted")
  end

  test "candidate identifier binds approval and repeated approvals reuse revision" do
    draft = OpenBlog::SaveDraft.call(content, actor: "Editor").post
    assert_refusal(:revision_mismatch) { publish({ approval: { name: "Reviewer", facts_checked: true, revision_identifier: "wrong" } }, post: draft) }
    result = publish({ approval: { name: "Reviewer", facts_checked: true, revision_identifier: draft.current_revision_identifier } }, post: draft)
    assert result.success?, result.error&.message
    repeat = publish({ approval: { name: "Reviewer", facts_checked: true } }, post: draft)
    assert repeat.success?
    assert_equal 2, draft.approvals.count
    assert_equal 1, draft.revisions.count
    assert_equal 1, draft.publications.count
  end

  test "approval gate checks candidate content and accepts human written posts" do
    OpenBlog.config.require_approval = true
    assert_refusal(:approval_required) { publish }
    assert_refusal(:approval_required) { publish(approval: { name: "Reviewer", facts_checked: false }) }
    approved = publish(approval: { name: "Reviewer", facts_checked: true })
    assert approved.success?, approved.error&.message
    assert_refusal(:approval_required) { publish({ body: "A new recommendation", change: "substantive" }, post: approved.post) }
    human = publish(slug: "human", provenance: "human_written")
    assert human.success?, human.error&.message
  end

  test "host refusal rolls back taxonomy FAQ and records" do
    OpenBlog.config.before_publish = ->(post, context) { assert_equal "Editor", context[:actor]; [ "Needs review" ] }
    result = assert_refusal(:refused_by_host) { publish(category: "Uncommitted", faq: [ { question: "When?", answer: "Spring." } ]) }
    assert_equal [ "Needs review" ], result.error.details
    refute OpenBlog::Category.exists?(name: "Uncommitted")
    OpenBlog.config.before_publish = ->(_post, _context) { nil }
    assert publish.success?
  end

  test "approval on a draft stores a revision without publication" do
    result = OpenBlog::SaveDraft.call(content.merge(approval: { name: "Reviewer", facts_checked: true }), actor: "Editor")
    assert result.success?, result.error&.message
    assert result.post.draft?
    assert_equal 1, result.post.revisions.count
    assert_equal 1, result.post.approvals.count
    assert_empty result.post.publications
    assert_nil result.post.public_revision
  end

  test "future publication queues after commit and schedule edits preserve intent" do
    due = @now + 1.hour
    result = publish(publish_at: due)
    assert result.success?, result.error&.message
    assert result.post.scheduled?
    assert_equal due, result.post.publish_at
    assert_nil result.records[:publication]
    assert_empty result.post.publications
    edit = OpenBlog::SaveDraft.call({ title: "Updated beans" }, post: result.post, actor: "Editor", now: @now)
    assert edit.success?
    assert edit.post.scheduled?
    assert_equal due, edit.post.publish_at
    cancel = publish({ publish_at: nil }, post: edit.post)
    assert cancel.success?
    assert cancel.post.draft?
    assert_nil cancel.post.publish_at
    assert_empty cancel.post.publications
  end

  test "saving a draft cannot turn it into a scheduled publication" do
    result = assert_refusal(:validation_failed) do
      OpenBlog::SaveDraft.call(content.merge(publish_at: @now + 1.hour), actor: "Editor", now: @now)
    end
    assert_includes result.error.details, "publish_at"
  end

  test "malformed schedule strings refuse without publishing" do
    [ "", "nonsense", "2026-99-99" ].each do |value|
      assert_refusal(:validation_failed) { publish(publish_at: value) }
    end
  end

  test "provenance change records actor evidence without a release" do
    post = publish.post
    result = publish({ provenance: "ai_assisted" }, post: post)
    assert result.success?
    assert_equal "ai_assisted", result.post.provenance
    assert_includes result.post.provenance_evidence, "Editor"
    assert_includes result.post.provenance_evidence, @now.iso8601
    assert_nil result.records[:publication]
  end

  test "stale operation objects merge partial updates against the locked stored post" do
    post = publish.post
    stale = OpenBlog::Post.find(post.id)
    first = publish({ title: "New title", change: "substantive" }, post: post)
    second = publish({ body: "New body", change: "substantive" }, post: stale)
    assert first.success?
    assert second.success?, second.error&.message
    stored = post.reload
    assert_equal "New title", stored.title
    assert_equal "New body", stored.body_markdown
    assert_equal OpenBlog::RevisionPayload.new(stored).identifier, stored.public_revision.identifier
  end

  test "FAQ replacements produce exactly one revision and preserve payload" do
    post = publish(faq: [ { question: "When?", answer: "Spring." } ]).post
    result = publish({ faq: [ { question: "Where?", answer: "Outside." }, { question: "How?", answer: "In rows." } ], change: "substantive" }, post: post)
    assert result.success?, result.error&.message
    assert_equal 2, result.post.faqs.count
    assert_equal 2, result.post.publications.count
    assert_equal OpenBlog::RevisionPayload.new(result.post.reload).identifier, result.post.public_revision.identifier
  end

  test "slug moves update redirect chains in the same transaction" do
    post = publish.post
    moved = publish({ slug: "beans-two" }, post: post)
    assert moved.success?, moved.error&.message
    moved = publish({ slug: "beans-three" }, post: moved.post)
    assert moved.success?
    assert_equal [ "/blog/beans-three" ], OpenBlog::Redirect.where(post: post).distinct.pluck(:new_path)
    assert_equal 2, OpenBlog::Redirect.where(post: post).count
  end

  test "connection declarations are appended and malformed input rolls back" do
    declaration = { connections: [], third_party_paid: false, declared_by: "Editor", declared_on: "2026-04-05" }
    result = publish(connections: declaration)
    assert result.success?, result.error&.message
    assert_equal "Editor", result.post.connection_declarations.first.recorded_by
    assert_refusal(:validation_failed) { publish({ connections: declaration.merge(third_party_paid: "yes") }, post: result.post) }
  end

  private
    def content
      { title: "Growing beans", slug: "growing-beans", body: "Plant in spring." }
    end

    def publish(attributes = {}, post: nil, now: @now, **keywords)
      input = post ? attributes.merge(keywords) : content.merge(attributes).merge(keywords)
      OpenBlog::Publish.call(input, post: post, actor: "Editor", now: now)
    end

    def assert_refusal(code)
      models = [ OpenBlog::Post, OpenBlog::Author, OpenBlog::Category, OpenBlog::Tag, OpenBlog::Faq, OpenBlog::Revision, OpenBlog::Approval, OpenBlog::Publication, OpenBlog::ConnectionDeclaration ]
      before = models.map(&:count)
      result = yield
      refute result.success?
      assert_equal code, result.error.code
      assert_equal before, models.map(&:count)
      result
    end
end
