require_relative "test_helper"
require "timeout"

class ApiPageConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @hook = OpenBlog.config.authenticate
    OpenBlog.config.authenticate = ->(_) { OpenBlog::Actor.new(name: "Draft editor", scopes: [ "write" ]) }
  end
  teardown do
    OpenBlog.config.authenticate = @hook
    OpenBlog::Page.where(kind: "editorial").delete_all
  end

  test "a draft writer cannot edit a page published while it waits for the row lock" do
    skip "PostgreSQL row locks" unless ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
    page = OpenBlog::Page.create!(kind: "editorial", title: "Editorial", body_markdown: "Original process.")
    pid_queue = Queue.new
    thread = nil
    OpenBlog::Page.transaction do
      page.lock!
      page.update!(status: "published")
      thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          pid_queue << connection.select_value("SELECT pg_backend_pid()")
          session = ActionDispatch::Integration::Session.new(Rails.application)
          session.put "/blog/api/v1/pages/editorial", params: { body: "Unapproved replacement." }, as: :json
          [ session.response.status, session.response.parsed_body ]
        end
      end
      pid = Timeout.timeout(5) { pid_queue.pop }
      assert_waiting(pid)
    end
    status, body = Timeout.timeout(5) { thread.value }
    assert_equal 403, status
    assert_equal "scope_required", body.dig("error", "code")
    assert_equal [ "publish" ], body.dig("error", "details")
    assert_equal "Original process.", page.reload.body_markdown
    assert_equal "published", page.status
  ensure
    thread&.join(5)
  end

  test "two first writes safely upsert the same kind" do
    skip "PostgreSQL unique index serialization" unless ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
    ready, start = Queue.new, Queue.new
    threads = 2.times.map do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          session = ActionDispatch::Integration::Session.new(Rails.application)
          session.put "/blog/api/v1/pages/editorial", params: { title: "Editorial #{index}", body: "Process #{index}." }, as: :json
          session.response.status
        end
      end
    end
    2.times { Timeout.timeout(5) { ready.pop } }
    2.times { start << true }
    assert_equal [ 200, 201 ], Timeout.timeout(10) { threads.map(&:value).sort }
    assert_equal 1, OpenBlog::Page.where(kind: "editorial").count
  ensure
    threads&.each { |thread| thread.join(5) }
  end

  private

  def assert_waiting(pid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
    loop do
      ActiveRecord::Base.connection.execute("SELECT pg_stat_clear_snapshot()")
      return assert(true) if ActiveRecord::Base.connection.select_value("SELECT wait_event_type FROM pg_stat_activity WHERE pid = #{Integer(pid)}") == "Lock"
      flunk "The write did not wait for the current page row" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      sleep 0.01
    end
  end
end
