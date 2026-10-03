require_relative "test_helper"
require "open_blog/reader_dates"

class ReaderDatesTest < ActiveSupport::TestCase
  test "visible dates are independently filtered against the response time" do
    now = Time.utc(2026, 9, 15, 12)
    post = OpenBlog::Post.new(published_at: now + 3600, modified_at: now - 3600)
    assert_nil OpenBlog::ReaderDates.published_at(post, now: now)
    assert_equal now - 3600, OpenBlog::ReaderDates.modified_at(post, now: now)
    post.published_at, post.modified_at = now, nil
    assert_equal now, OpenBlog::ReaderDates.published_at(post, now: now)
    assert_nil OpenBlog::ReaderDates.modified_at(post, now: now)
  end

  test "Atom uses the last nonfuture publication when modification is unknown" do
    now = Time.utc(2026, 9, 15, 12)
    result = OpenBlog::Publish.call({ title: "Orchard", slug: "orchard", body: "Tree notes." }, actor: "Editor", now: now - 3600)
    assert result.success?, result.error&.message
    post = result.post
    post.modified_at = nil
    post.publications.create!(revision: post.public_revision, entry_type: "adopted", occurred_at: now - 1800)
    post.publications.create!(revision: post.public_revision, entry_type: "maintenance", occurred_at: now - 900)
    post.publications.create!(revision: post.public_revision, entry_type: "maintenance", occurred_at: now + 1800)
    assert_equal now - 1800, OpenBlog::ReaderDates.feed_updated_at(post, now: now)
    post.modified_at = now - 60
    assert_equal now - 60, OpenBlog::ReaderDates.feed_updated_at(post, now: now)
  end

  test "Atom required time falls back to creation then response time without changing data" do
    now = Time.utc(2026, 9, 15, 12)
    post = OpenBlog::Post.new(created_at: now - 60)
    assert_equal now - 60, OpenBlog::ReaderDates.feed_updated_at(post, now: now)
    post.created_at = now + 60
    before = post.attributes.deep_dup
    assert_equal now, OpenBlog::ReaderDates.feed_updated_at(post, now: now)
    assert_equal before, post.attributes
  end
end
