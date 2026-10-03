require_relative "test_helper"
require "rake"

class ScheduledPublicationTest < ActiveSupport::TestCase
  setup do
    @settings = %i[require_approval before_publish policy_urls].to_h { |key| [ key, OpenBlog.config.public_send(key) ] }
    @now = Time.current.change(usec: 0)
  end
  teardown { @settings.each { |key, value| OpenBlog.config.public_send("#{key}=", value) } }

  test "due job publishes current content at actual release time and duplicate jobs are harmless" do
    post = schedule
    edited = OpenBlog::SaveDraft.call({ body: "The revised planting instructions." }, post: post, actor: "Editor")
    assert edited.success?
    travel_to @now + 2.hours do
      assert_difference("OpenBlog::Publication.count", 1) { OpenBlog::PublishScheduledPostJob.perform_now(post.id) }
      post.reload
      assert post.published?
      assert_nil post.publish_at
      assert_equal Time.current, post.published_at
      assert_equal Time.current, post.modified_at
      assert_equal "The revised planting instructions.", JSON.parse(post.public_revision.payload).fetch("body")
      assert_nil post.public_revision.actor
      assert_nil post.publications.first.released_by
      assert_equal "first", post.publications.first.entry_type
      assert_no_difference("OpenBlog::Publication.count") { OpenBlog::PublishScheduledPostJob.perform_now(post.id) }
    end
  end

  test "missing cancelled future and already public posts are no ops" do
    future = schedule
    cancelled = schedule
    OpenBlog::Unpublish.call(cancelled, actor: "Editor")
    assert_no_difference("OpenBlog::Publication.count") do
      [ -1, future.id, cancelled.id ].each { |id| OpenBlog::PublishScheduledPostJob.perform_now(id) }
    end
    assert future.reload.scheduled?
    assert cancelled.reload.draft?
  end

  test "an old job cannot release a post rescheduled to a later time" do
    post = schedule
    result = OpenBlog::Publish.call({ publish_at: @now + 3.hours }, post: post, actor: "Editor", now: @now)
    assert result.success?
    travel_to @now + 1.hour do
      OpenBlog::PublishScheduledPostJob.perform_now(post.id)
      assert post.reload.scheduled?
      assert_empty post.publications
    end
    travel_to @now + 3.hours do
      OpenBlog::PublishScheduledPostJob.perform_now(post.id)
      assert post.reload.published?
      assert_equal Time.current, post.published_at
    end
  end

  test "background release leaves changed approval missing while normal publication keeps its gate" do
    OpenBlog.config.require_approval = true
    OpenBlog.config.policy_urls = { responsible_party: "https://publisher.example/about" }
    post = schedule(approval: { name: "Avery", facts_checked: true })
    assert OpenBlog::SaveDraft.call({ body: "Changed after review." }, post: post, actor: "Editor").success?
    travel_to @now + 2.hours do
      refused = OpenBlog::Publish.call({}, post: post, actor: "Editor")
      assert_equal :approval_required, refused.error.code
      OpenBlog::PublishScheduledPostJob.perform_now(post.id)
      post.reload
      assert post.published?
      assert_equal :ai_assisted, OpenBlog::LabelPolicy.for(post)
      assert_includes OpenBlog::Findings.for(post).pluck(:code), :approval_absent
      assert_equal 1, post.approvals.count
      refute_equal post.public_revision_id, post.approvals.first.revision_id
    end
  end

  test "host refusal remains effective and raises the typed error to the job runner" do
    post = schedule
    OpenBlog.config.before_publish = ->(*) { [ "Editorial pause" ] }
    travel_to @now + 2.hours do
      error = assert_raises(OpenBlog::Error::RefusedByHost) { OpenBlog::PublishScheduledPostJob.perform_now(post.id) }
      assert_includes error.details, "Editorial pause"
      assert post.reload.scheduled?
      assert_empty post.publications
    end
  end

  test "scheduled republication records changed content as substantive without inventing classification input" do
    result = OpenBlog::Publish.call({ title: "Seasonal notes", body: "Earlier notes." }, actor: "Editor", now: @now - 1.day)
    post = result.post
    OpenBlog::Unpublish.call(post, actor: "Editor", now: @now)
    assert OpenBlog::Publish.call({ publish_at: @now + 1.hour }, post: post, actor: "Editor", now: @now).success?
    assert OpenBlog::SaveDraft.call({ body: "Updated seasonal notes." }, post: post, actor: "Editor", now: @now).success?
    travel_to @now + 2.hours do
      OpenBlog::PublishScheduledPostJob.perform_now(post.id)
      assert post.reload.published?
      assert_equal "substantive", post.publications.order(:id).last.entry_type
      assert_equal Time.current, post.modified_at
      assert_equal @now - 1.day, post.published_at
    end
  end

  test "publish due task uses the same job path and skips future schedules" do
    due = schedule
    future = schedule(publish_at: @now + 3.hours)
    previous = Rake.application
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load OpenBlog::Engine.root.join("lib/tasks/open_blog.rake")
    travel_to @now + 2.hours do
      Rake::Task["open_blog:publish_due"].invoke
      assert due.reload.published?
      assert future.reload.scheduled?
    end
  ensure
    Rake.application = previous
  end

  private

  def schedule(**attributes)
    result = OpenBlog::Publish.call({ title: "Planting note #{SecureRandom.hex(4)}", body: "Original planting instructions.",
      provenance: "ai_assisted", publish_at: @now + 1.hour }.merge(attributes), actor: "Editor", now: @now)
    assert result.success?, result.error&.message
    result.post
  end
end
