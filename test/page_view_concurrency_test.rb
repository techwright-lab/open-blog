require_relative "test_helper"
require "timeout"

class PageViewConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "simultaneous first counts and increments lose no views" do
    initial_author_ids = OpenBlog::Author.ids.sort
    threads = nil
    author = OpenBlog::Author.create!(name: "Concurrent count editor", slug: "count-editor-#{SecureRandom.hex(8)}")
    post = OpenBlog::Post.create!(title: "Concurrent views", slug: "concurrent-views-#{SecureRandom.hex(8)}", author: author, author_name: author.name, status: "draft")
    post.update_column(:status, "published")
    request = ActionDispatch::TestRequest.create
    request.set_header("HTTP_USER_AGENT", "Mozilla/5.0 Reader")
    request.set_header("HTTP_ACCEPT", "text/html")
    now = Time.utc(2026, 10, 6)
    2.times do |round|
      ready, start = Queue.new, Queue.new
      threads = 2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            start.pop
            OpenBlog::PageViews.count!(post, request, now: now)
          end
        end
      end
      2.times { Timeout.timeout(5) { ready.pop } }
      2.times { start << true }
      Timeout.timeout(5) { threads.each(&:value) }
      assert_equal (round + 1) * 2, OpenBlog::PageView.uncached { OpenBlog::PageView.find_by!(post: post, day: now.to_date).views }
    end
  ensure
    threads&.each { |thread| thread.join(5) }
    OpenBlog::PageView.where(post_id: post&.id).delete_all
    post&.delete
    author&.delete
    assert_equal initial_author_ids, OpenBlog::Author.ids.sort
  end
end
