require_relative "test_helper"

class ScheduleCommitTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  self.use_transactional_tests = false

  teardown do
    OpenBlog::Post.where(slug: %w[committed-schedule cancelled-schedule]).destroy_all
    OpenBlog::Author.where(name: "Schedule Writer").delete_all
    clear_enqueued_jobs
  end

  test "scheduled job is queued only when the outer transaction commits" do
    now = Time.current.change(usec: 0)
    due = now + 1.hour
    result = nil
    clear_enqueued_jobs
    assert_enqueued_with(job: OpenBlog::PublishScheduledPostJob, at: due) do
      OpenBlog::Post.transaction do
        result = OpenBlog::Publish.call({ title: "A planned note", slug: "committed-schedule", author: "Schedule Writer", publish_at: due }, actor: "Editor", now: now)
        assert result.success?, result.error&.message
        assert_enqueued_jobs 0
      end
    end
    assert_equal [ result.post.id ], enqueued_jobs.last[:args]
  end

  test "rescheduling queues a new due time while ordinary edits queue nothing" do
    now = Time.current.change(usec: 0)
    due = now + 1.hour
    first = OpenBlog::Publish.call({ title: "A planned note", slug: "committed-schedule", author: "Schedule Writer", publish_at: due }, actor: "Editor", now: now)
    assert first.success?
    clear_enqueued_jobs
    assert_no_enqueued_jobs do
      edit = OpenBlog::SaveDraft.call({ title: "An edited plan" }, post: first.post, actor: "Editor", now: now)
      assert edit.success?
      assert_equal due, edit.post.publish_at
    end
    assert_enqueued_with(job: OpenBlog::PublishScheduledPostJob, at: due + 1.hour) do
      edit = OpenBlog::SaveDraft.call({ publish_at: due + 1.hour }, post: first.post, actor: "Editor", now: now)
      assert edit.success?
    end
  end

  test "outer rollback leaves no scheduled job or post" do
    clear_enqueued_jobs
    assert_no_enqueued_jobs do
      OpenBlog::Post.transaction do
        result = OpenBlog::Publish.call({ title: "A cancelled note", slug: "cancelled-schedule", author: "Schedule Writer", publish_at: 1.hour.from_now }, actor: "Editor")
        assert result.success?
        raise ActiveRecord::Rollback
      end
    end
    refute OpenBlog::Post.exists?(slug: "cancelled-schedule")
  end
end
