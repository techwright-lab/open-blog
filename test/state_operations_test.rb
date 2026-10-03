require_relative "test_helper"
require "minitest/mock"

class StateOperationsTest < ActiveSupport::TestCase
  setup do
    @author = OpenBlog::Author.create!(name: "Morgan Editor", slug: "morgan-editor")
    @now = Time.utc(2026, 10, 3, 12)
  end

  test "approval records the public revision and preserves a false answer" do
    post, revision = public_post
    [ true, false ].each do |answer|
      result = OpenBlog::Approve.call(post, revision_identifier: revision.identifier,
        name: "Casey Reader", facts_checked: answer, actor: "review-agent", now: @now)
      assert result.success?, result.error&.message
      assert_equal({ revision: "same", publication: nil, approval: "sent" }, result.records)
      approval = post.approvals.order(:id).last
      assert_equal revision, approval.revision
      assert_equal "Casey Reader", approval.reviewer_name
      assert_equal answer, approval.facts_checked
      assert_equal "review-agent", approval.recorded_by
      assert_equal @now, approval.approved_at
    end
    assert_equal 1, post.revisions.count
    assert_equal 1, post.publications.count
  end

  test "approval refuses malformed evidence and stale or absent public revisions" do
    post, revision = public_post
    [ [ "", true ], [ nil, true ], [ [], true ], [ "Reader", nil ], [ "Reader", "false" ], [ "Reader", 0 ] ].each do |name, checked|
      assert_no_difference("OpenBlog::Approval.count") do
        result = OpenBlog::Approve.call(post, revision_identifier: revision.identifier,
          name: name, facts_checked: checked, actor: "review-agent", now: @now)
        assert_equal :approval_incomplete, result.error.code
        assert_equal 422, result.error.status
      end
    end
    [ [ post, "f" * 64 ], [ draft, revision.identifier ] ].each do |target, identifier|
      assert_no_difference("OpenBlog::Approval.count") do
        result = OpenBlog::Approve.call(target, revision_identifier: identifier,
          name: "Reader", facts_checked: true, actor: "review-agent", now: @now)
        assert_equal :revision_mismatch, result.error.code
        assert_equal 409, result.error.status
      end
    end
  end

  test "approval checks fresh public state when the supplied instance is stale" do
    post, old_revision = public_post
    fresh = OpenBlog::Post.find(post.id)
    newer = fresh.revisions.create!(identifier: "d" * 64, payload: "replacement")
    fresh.update_columns(public_revision_id: newer.id)
    result = OpenBlog::Approve.call(post, revision_identifier: old_revision.identifier,
      name: "Reader", facts_checked: true, actor: "review-agent", now: @now)
    assert_equal :revision_mismatch, result.error.code
    assert_empty post.approvals
  end

  test "unpublish retains publication history and records a removed URL" do
    post, revision = public_post
    result = OpenBlog::Unpublish.call(post, actor: "editor", now: @now)
    assert result.success?, result.error&.message
    assert result.post.draft?
    assert_nil result.post.publish_at
    assert_equal revision, result.post.public_revision
    assert_equal 1, post.publications.count
    redirect = OpenBlog::Redirect.find_by!(old_path: post.path)
    assert_equal "unpublish", redirect.source
    assert_nil redirect.new_path
    assert_equal post.id, redirect.post_id
    assert_equal @now.to_date, redirect.occurred_on
    assert_equal({ revision: nil, publication: nil, approval: nil }, result.records)
  end

  test "unpublish cancels a schedule and does not create a redirect for an unpublished post" do
    post = draft(status: "scheduled", publish_at: @now + 3600)
    assert_no_difference("OpenBlog::Redirect.count") do
      result = OpenBlog::Unpublish.call(post, actor: "editor", now: @now)
      assert result.success?, result.error&.message
      assert result.post.draft?
      assert_nil result.post.publish_at
    end
  end

  test "remove archives a public post and flattens earlier redirects" do
    post, revision = public_post
    historical = OpenBlog::Redirect.create!(old_path: "/blog/previous-title", new_path: post.path,
      source: "slug_change", post: post, occurred_on: @now.to_date - 10)
    result = OpenBlog::Remove.call(post, redirect_to: "/blog/replacement", actor: "editor", now: @now)
    assert result.success?, result.error&.message
    assert result.post.archived?
    assert_nil result.post.publish_at
    assert_equal revision, result.post.public_revision
    redirect = OpenBlog::Redirect.find_by!(old_path: post.path)
    assert_equal "removal", redirect.source
    assert_equal "/blog/replacement", redirect.new_path
    assert_equal "/blog/replacement", historical.reload.new_path
    assert_equal "slug_change", historical.source
    assert_equal @now.to_date - 10, historical.occurred_on
  end

  test "removal resolves an existing redirect target and refuses loops" do
    post, = public_post
    OpenBlog::Redirect.create!(old_path: "/blog/alias", new_path: "/blog/destination",
      source: "manual", occurred_on: @now.to_date)
    result = OpenBlog::Remove.call(post, redirect_to: "/blog/alias", actor: "editor", now: @now)
    assert result.success?, result.error&.message
    assert_equal "/blog/destination", OpenBlog::Redirect.find_by!(old_path: post.path).new_path

    other, = public_post
    result = OpenBlog::Remove.call(other, redirect_to: other.path, actor: "editor", now: @now)
    assert_equal :validation_failed, result.error.code
    assert other.reload.published?
    assert_nil OpenBlog::Redirect.find_by(old_path: other.path)
  end

  test "removal refuses malformed redirect destinations without changing public state" do
    post, = public_post
    [ "relative", "javascript:alert(1)", "https://", "//example.test/path", "" ].each do |target|
      result = OpenBlog::Remove.call(post, redirect_to: target, actor: "editor", now: @now)
      assert_equal :validation_failed, result.error.code
      assert post.reload.published?
    end
    assert_empty OpenBlog::Redirect.all
  end

  test "absolute URLs for the current page cannot disguise a redirect loop" do
    original_base = OpenBlog.config.public_base_url
    OpenBlog.config.public_base_url = "https://journal.example"
    post, = public_post
    [ "#{post.url}?view=latest", "#{post.url}#details" ].each do |target|
      result = OpenBlog::Remove.call(post, redirect_to: target, actor: "editor", now: @now)
      assert_equal :validation_failed, result.error.code
      assert post.reload.published?
    end
  ensure
    OpenBlog.config.public_base_url = original_base
  end

  test "remove deletes unrecorded drafts and schedules including their children" do
    %w[draft scheduled].each do |status|
      post = draft(status: status, publish_at: (status == "scheduled" ? @now + 3600 : nil))
      post.faqs.create!(question: "How often?", answer: "Weekly.", position: 1)
      assert_difference("OpenBlog::Post.count", -1) do
        result = OpenBlog::Remove.call(post, actor: "editor", now: @now)
        assert result.success?, result.error&.message
        assert result.post.destroyed?
      end
      assert_empty OpenBlog::Faq.where(post_id: post.id)
    end
    assert_empty OpenBlog::Redirect.all
  end

  test "remove preserves approved drafts and declared connections" do
    post = draft
    revision = post.revisions.create!(identifier: post.current_revision_identifier, payload: "recorded")
    post.approvals.create!(revision: revision, kind: "sent", reviewer_name: "Reader",
      facts_checked: true, approved_at: @now)
    other = draft(status: "scheduled", publish_at: @now + 3600)
    other.connection_declarations.create!(connections: [], third_party_paid: false,
      declared_by: "Editor", declared_on: @now.to_date)
    [ post, other ].each do |target|
      assert_no_difference("OpenBlog::Post.count") do
        result = OpenBlog::Remove.call(target, actor: "editor", now: @now)
        assert result.success?, result.error&.message
        assert result.post.archived?
        assert_nil result.post.publish_at
      end
    end
    assert_equal 1, post.approvals.count
    assert_equal 1, other.connection_declarations.count
  end

  test "repeated transitions preserve redirect history and removed paths stay removed" do
    post, = public_post
    assert OpenBlog::Unpublish.call(post, actor: "editor", now: @now).success?
    redirect = OpenBlog::Redirect.find_by!(old_path: post.path)
    assert_no_difference("OpenBlog::Redirect.count") do
      assert OpenBlog::Unpublish.call(post, actor: "editor", now: @now + 3600).success?
      assert OpenBlog::Remove.call(post, actor: "editor", now: @now + 7200).success?
    end
    assert_equal "unpublish", redirect.reload.source
    assert_equal @now.to_date, redirect.occurred_on
    assert_nil redirect.new_path
  end

  test "redirect write failures roll back the state transition" do
    post, = public_post
    occupied = OpenBlog::Redirect.create!(old_path: post.path, source: "manual",
      occurred_on: @now.to_date, new_path: "/blog/other-owner")
    result = OpenBlog::Remove.call(post, actor: "editor", now: @now)
    refute result.success?
    assert_equal :slug_reserved, result.error.code
    assert post.reload.published?
    assert_equal "/blog/other-owner", occupied.reload.new_path
  end

  test "reclaiming a former slug keeps its live URL free of redirects" do
    post, = public_post
    original_slug, original_path = post.slug, post.path
    moved = OpenBlog::Publish.call({ slug: "new-orchard" }, post: post, actor: "editor", now: @now)
    assert moved.success?, moved.error&.message
    returned = OpenBlog::Publish.call({ slug: original_slug }, post: moved.post, actor: "editor", now: @now)
    assert returned.success?, returned.error&.message
    assert_nil OpenBlog::Redirect.find_by(old_path: original_path)
    assert_equal original_path, OpenBlog::Redirect.find_by!(old_path: "/blog/new-orchard").new_path
  end

  test "editing an unpublished slug keeps its former public URL removed" do
    post, = public_post
    original_path = post.path
    assert OpenBlog::Unpublish.call(post, actor: "editor", now: @now).success?
    changed = OpenBlog::SaveDraft.call({ slug: "revised-orchard" }, post: post, actor: "editor", now: @now)
    assert changed.success?, changed.error&.message
    assert_nil OpenBlog::Redirect.find_by!(old_path: original_path).new_path
  end

  test "a redirect persistence failure rolls back the saved status" do
    post, = public_post
    OpenBlog::Redirect.stub(:create!, ->(**) { raise OpenBlog::Error::ValidationFailed }) do
      result = OpenBlog::Unpublish.call(post, actor: "editor", now: @now)
      assert_equal :validation_failed, result.error.code
    end
    assert post.reload.published?
    assert_empty OpenBlog::Redirect.all
  end

  test "an explicit post wins over another posts external identity during publication" do
    target = draft(external_id: "orchard-item")
    other = draft(external_id: "other-item")
    result = OpenBlog::Publish.call({ external_id: other.external_id, title: "Updated orchard" },
      post: target, actor: "editor", now: @now)
    assert result.success?, result.error&.message
    assert_equal target.id, result.post.id
    assert_equal "orchard-item", result.post.external_id
    assert_equal "Updated orchard", target.reload.title
    assert_equal "Home orchard", other.reload.title
    assert other.draft?
    assert_empty other.revisions
    assert_empty other.publications
  end

  test "republishing changed draft content requires an explicit change" do
    post, revision = public_post
    first_date = post.published_at
    assert OpenBlog::Unpublish.call(post, actor: "editor", now: @now).success?
    edit = OpenBlog::SaveDraft.call({ body: "Prune in winter." }, post: post, actor: "editor", now: @now)
    assert edit.success?, edit.error&.message
    assert_equal revision, edit.post.public_revision
    assert_no_difference [ "OpenBlog::Revision.count", "OpenBlog::Publication.count" ] do
      refused = OpenBlog::Publish.call({}, post: edit.post, actor: "editor", now: @now)
      assert_equal :change_type_required, refused.error.code
    end
    assert post.reload.draft?
    assert_equal "Prune in winter.", post.body_markdown
    result = OpenBlog::Publish.call({ change: "substantive" }, post: post, actor: "editor", now: @now)
    assert result.success?, result.error&.message
    assert_equal "substantive", result.records[:publication]
    assert_equal first_date, result.post.published_at
    assert_equal @now, result.post.modified_at
    assert_equal 1, post.publications.where(entry_type: "first").count
    assert_equal 2, post.revisions.count
  end

  test "republishing an archived post retains its revision and original dates" do
    post, revision = public_post
    first_date = post.published_at
    removed = OpenBlog::Remove.call(post, actor: "editor", now: @now)
    assert removed.success?, removed.error&.message
    assert removed.post.archived?
    result = OpenBlog::Publish.call({}, post: removed.post, actor: "editor", now: @now + 3600)
    assert result.success?, result.error&.message
    assert result.post.published?
    assert_equal revision, result.post.public_revision
    assert_equal first_date, result.post.published_at
    assert_equal first_date, result.post.modified_at
    assert_equal "maintenance", result.records[:publication]
    assert_equal "republished", post.publications.order(:id).last.description
    assert_equal 1, post.revisions.count
    assert_equal 1, post.publications.where(entry_type: "first").count
    assert_nil OpenBlog::Redirect.find_by(old_path: post.path)
  end

  private

  def draft(**attributes)
    OpenBlog::Post.create!({ title: "Home orchard", slug: "orchard-#{OpenBlog::Post.count}",
      author: @author, author_name: @author.name, body_markdown: "Trees need care." }.merge(attributes))
  end

  def public_post
    post = draft
    revision = post.revisions.create!(identifier: post.current_revision_identifier, payload: OpenBlog::RevisionPayload.new(post).to_json)
    post.publications.create!(revision: revision, entry_type: "first", occurred_at: @now - 3600)
    post.update_columns(status: "published", public_revision_id: revision.id,
      published_at: @now - 3600, modified_at: @now - 3600)
    [ post, revision ]
  end
end
