require_relative "test_helper"
require "minitest/mock"

class RecordReleaseTest < ActiveSupport::TestCase
  setup do
    @author = OpenBlog::Author.create!(name: "Casey Finch", slug: "casey-finch")
    @first_time = Time.utc(2026, 9, 1, 10)
    @later_time = @first_time + 2.days
  end

  test "first release records persisted content actor and dates together" do
    post = build_post
    post.faqs.build(position: 1, question: "Which season?", answer: "Late summer.")
    release(post, actor: "editor", made_by_ai: false)

    assert_equal({ revision: "new", publication: "first", approval: nil }, post.release_records)
    revision = post.public_revision
    assert_equal OpenBlog::RevisionPayload.new(post.reload).to_json, revision.payload
    assert_equal "editor", revision.actor
    assert_equal false, revision.made_by_ai
    assert_equal @first_time, revision.created_at
    assert_equal @first_time, post.published_at
    assert_equal @first_time, post.modified_at
    assert_equal "editor", post.publications.sole.released_by
    assert_nil post.release_context
  end

  test "publication records determine dates even when callers assign date fields" do
    post = build_post(published_at: @first_time - 1.year, modified_at: @first_time - 1.month)
    release(post)
    assert_equal @first_time, post.published_at
    assert_equal @first_time, post.modified_at
    post.update!(published_at: @later_time, modified_at: @later_time)
    assert_equal @first_time, post.published_at
    assert_equal @first_time, post.modified_at
  end

  test "draft and scheduled saves create no release records" do
    %w[draft scheduled].each do |status|
      post = build_post(slug: status, status: status)
      assert_no_difference [ "OpenBlog::Revision.count", "OpenBlog::Publication.count" ] do
        post.save!
      end
      assert_nil post.public_revision
    end
  end

  test "metadata saves and identical saves preserve editorial dates and records" do
    post = release(build_post)
    revision_id = post.public_revision_id
    assert_no_difference [ "OpenBlog::Revision.count", "OpenBlog::Publication.count" ] do
      post.update!(featured: true, canonical_url: "https://example.test/original")
      post.save!
    end
    assert_equal revision_id, post.public_revision_id
    assert_equal @first_time, post.modified_at
    assert_equal({ revision: "same", publication: nil, approval: nil }, post.release_records)
  end

  test "direct public edit defaults to substantive with no actor or approval" do
    post = release(build_post)
    travel_to(@later_time) { post.update!(title: "Watering in autumn") }
    assert_equal 2, post.revisions.count
    entry = post.publications.order(:id).last
    assert_equal "substantive", entry.entry_type
    assert_nil entry.released_by
    assert_nil entry.revision.actor
    assert_empty post.approvals
    assert_equal @later_time, post.modified_at
    assert_equal @first_time, post.published_at
  end

  test "explicit change types control dates even for an unchanged revision" do
    post = release(build_post)
    %w[maintenance substantive correction].each_with_index do |change, index|
      time = @later_time + index.days
      post.release_context = { change: change, note: "Adjusted the growing instructions", actor: "reviewer", now: time,
        description: "Seasonal update" }
      assert_no_difference "OpenBlog::Revision.count" do
        assert_difference "OpenBlog::Publication.count", 1 do
          post.save!
        end
      end
      entry = post.publications.order(:id).last
      assert_equal change, entry.entry_type
      assert_equal "Seasonal update", entry.description
      assert_equal "Adjusted the growing instructions", entry.note
      assert_equal(change == "maintenance" ? @first_time : time, post.modified_at)
    end
  end

  test "changed maintenance keeps dates and reverting content reuses its immutable revision" do
    post = release(build_post)
    first_revision = post.public_revision
    original_body = post.body_markdown
    post.release_context = { change: "maintenance", actor: "editor", now: @later_time }
    post.update!(body_markdown: "Use a larger watering can.")
    assert_equal @first_time, post.modified_at
    assert_equal "maintenance", post.publications.order(:id).last.entry_type
    assert_difference "OpenBlog::Revision.count", 0 do
      post.update!(body_markdown: original_body)
    end
    assert_equal first_revision.id, post.public_revision_id
    assert_equal "same", post.release_records[:revision]
  end

  test "recording an unchanged post again does not replay a previous status transition" do
    post = release(build_post)
    assert post.saved_change_to_status?
    assert_no_difference [ "OpenBlog::Revision.count", "OpenBlog::Publication.count" ] do
      records = OpenBlog::RecordRelease.call(post, actor: "reader", now: @later_time)
      assert_equal({ revision: "same", publication: nil, approval: nil }, records)
    end
  end

  test "saving a post destroys taggings marked for replacement" do
    post = release(build_post)
    tag = OpenBlog::Tag.create!(name: "Garden", slug: "garden")
    post.taggings.create!(tag: tag)
    post.taggings.reload.first.mark_for_destruction
    assert_difference "OpenBlog::Tagging.count", -1 do
      post.save!
    end
    assert_empty post.reload.tags
  end

  test "republishing the same content creates maintenance and retains the first date" do
    post = release(build_post)
    post.update!(status: "draft")
    release(post, now: @later_time)
    assert_equal 1, post.revisions.count
    assert_equal 1, post.publications.where(entry_type: "first").count
    entry = post.publications.order(:id).last
    assert_equal "maintenance", entry.entry_type
    assert_equal "republished", entry.description
    assert_equal @first_time, post.published_at
    assert_equal @first_time, post.modified_at
  end

  test "an approved draft revision is reused on its first public release" do
    post = build_post(status: "draft")
    post.save!
    revision = OpenBlog::Revision.create!(post: post, identifier: post.current_revision_identifier,
      payload: OpenBlog::RevisionPayload.new(post).to_json)
    assert_no_difference "OpenBlog::Revision.count" do
      release(post)
    end
    assert_equal revision.id, post.public_revision_id
    assert_equal "same", post.release_records[:revision]
    assert_equal "first", post.publications.sole.entry_type
  end

  test "adopted history never gains a first entry or an invented publication date" do
    post = build_post(status: "draft")
    post.save!
    revision = OpenBlog::Revision.create!(post: post, identifier: post.current_revision_identifier,
      payload: OpenBlog::RevisionPayload.new(post).to_json)
    OpenBlog::Publication.create!(post: post, revision: revision, entry_type: "adopted", occurred_at: @first_time)
    OpenBlog::Baseline.create!(post: post, adopted_revision: revision, adopted_at: @first_time, provenance: "unknown")
    post.update_columns(public_revision_id: revision.id)
    release(post, now: @later_time)
    assert_equal [ "adopted", "maintenance" ], post.publications.order(:id).pluck(:entry_type)
    assert_nil post.published_at
    assert_nil post.modified_at
    post.release_context = { change: "correction", note: "Corrected a measurement", now: @later_time }
    post.update!(body_markdown: "Two litres per pot.")
    assert_nil post.published_at
    assert_equal @later_time, post.modified_at
  end

  test "stale partial saves record the actual combined persisted content" do
    post = release(build_post)
    stale = OpenBlog::Post.find(post.id)
    stale.faqs.load
    post.update!(title: "Winter watering")
    post.faqs.create!(position: 1, question: "How often?", answer: "Once a week.")
    stale.update!(body_markdown: "Check the soil first.")
    stored = post.reload
    assert_equal "Winter watering", stored.title
    assert_equal "Check the soil first.", stored.body_markdown
    expected = OpenBlog::RevisionPayload.new(stored)
    assert_equal expected.identifier, stored.current_revision_identifier
    assert_equal expected.identifier, stored.public_revision.identifier
    assert_equal expected.to_json, stored.public_revision.payload
    assert_includes stored.search_text, "Winter watering"
    assert_includes stored.search_text, "Once a week."
    assert_equal 9, stored.word_count
  end

  test "rich text release records serialized persisted content" do
    previous_formats = OpenBlog.config.body_formats
    OpenBlog.config.body_formats = [ :markdown, :rich_text ]
    post = build_post(body_format: "rich_text")
    post.rich_body = "<p class='tip'>Water slowly<br/>Let it drain.</p>"
    release(post)
    assert_equal OpenBlog::RevisionPayload.new(post.reload).to_json, post.public_revision.payload
    post.rich_body = "<p>A revised <b>tip</b>.</p>"
    post.save!
    assert_equal OpenBlog::RevisionPayload.new(post.reload).to_json, post.public_revision.payload
    assert_equal 2, post.publications.count
  ensure
    OpenBlog.config.body_formats = previous_formats
  end

  test "failed publication rolls back content children pointer and dates" do
    post = release(build_post)
    original = post.attributes
    post.title = "A failed update"
    post.faqs.build(position: 1, question: "Will it save?", answer: "No.")
    post.release_context = { actor: "editor", now: @later_time }
    OpenBlog::Publication.stub(:create!, ->(**) { raise "publication unavailable" }) do
      assert_no_difference [ "OpenBlog::Revision.count", "OpenBlog::Publication.count", "OpenBlog::Faq.count" ] do
        error = assert_raises(RuntimeError) { post.save! }
        assert_equal "publication unavailable", error.message
      end
    end
    assert_nil post.release_context
    assert_equal original, post.reload.attributes
  end

  private

  def build_post(**attributes)
    OpenBlog::Post.new({ slug: "watering-notes", title: "Watering notes", author: @author,
      author_name: @author.name, body_markdown: "Give each pot some water.", status: "published" }.merge(attributes))
  end

  def release(post, **context)
    post.status = "published"
    post.release_context = { actor: "writer", now: @first_time }.merge(context)
    post.save!
    post
  end
end
