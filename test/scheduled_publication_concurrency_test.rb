require_relative "test_helper"
require "timeout"

class ScheduledPublicationConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    skip "PostgreSQL row locks" unless ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
    @author_ids = OpenBlog::Author.order(:id).pluck(:id)
    @author = OpenBlog::Author.create!(name: "Schedule race author", slug: "schedule-race-#{SecureRandom.hex(6)}")
    @post = OpenBlog::Publish.call({ author: @author, title: "Scheduled lock #{SecureRandom.hex(5)}", body: "A scheduled observation.", publish_at: 1.hour.ago },
      actor: "Editor", now: 2.hours.ago).post
  end

  teardown do
    if @post
      @post.update_columns(public_revision_id: nil)
      OpenBlog::Publication.where(post_id: @post.id).delete_all
      OpenBlog::Revision.where(post_id: @post.id).delete_all
      @post.destroy!
    end
    @author&.destroy!
    assert_equal @author_ids, OpenBlog::Author.order(:id).pluck(:id) if @author_ids
  end

  test "waiting job observes a cancellation committed before it obtains the row" do
    thread = nil
    pid_queue = Queue.new
    OpenBlog::Post.transaction do
      @post.lock!
      @post.update!(status: "draft", publish_at: nil)
      thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          pid_queue << connection.select_value("SELECT pg_backend_pid()")
          OpenBlog::PublishScheduledPostJob.perform_now(@post.id)
        end
      end
      assert_waiting(Timeout.timeout(5) { pid_queue.pop })
    end
    Timeout.timeout(5) { thread.value }
    assert @post.reload.draft?
    assert_empty @post.publications
  ensure
    thread&.join(5)
  end

  test "competing jobs create only one first publication" do
    ready, release = Queue.new, Queue.new
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          release.pop
          OpenBlog::PublishScheduledPostJob.perform_now(@post.id)
        end
      end
    end
    2.times { Timeout.timeout(5) { ready.pop } }
    2.times { release << true }
    Timeout.timeout(10) { threads.each(&:value) }
    assert @post.reload.published?
    assert_equal [ "first" ], @post.publications.pluck(:entry_type)
    assert_equal 1, @post.revisions.count
  ensure
    threads&.each { |thread| thread.join(5) }
  end

  private

  def assert_waiting(pid)
    connection = ActiveRecord::Base.connection
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
    loop do
      waiting = connection.uncached do
        connection.execute("SELECT pg_stat_clear_snapshot()")
        connection.select_value("SELECT wait_event_type FROM pg_stat_activity WHERE pid = #{Integer(pid)}") == "Lock"
      end
      return assert(true) if waiting
      flunk "The scheduled job must wait for the current row" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      sleep 0.01
    end
  end
end
