require_relative "test_helper"
require "timeout"

class RedirectConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "competing opposite redirects serialize before resolving their targets" do
    skip "PostgreSQL advisory lock" unless ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
    prefix = "/redirect-race-#{SecureRandom.hex(6)}"
    first_ready, second_pid, release, start_second = Queue.new, Queue.new, Queue.new, Queue.new
    first = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        OpenBlog::RedirectTarget.synchronize do
          OpenBlog::Redirect.create!(old_path: "#{prefix}-a", new_path: "#{prefix}-b", source: "manual", occurred_on: Date.current)
          first_ready << true
          release.pop
        end
      end
    end
    Timeout.timeout(5) { first_ready.pop }
    second = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        second_pid << connection.select_value("SELECT pg_backend_pid()")
        start_second.pop
        OpenBlog::RedirectTarget.synchronize do
          target = OpenBlog::RedirectTarget.call("#{prefix}-a", from: "#{prefix}-b")
          OpenBlog::Redirect.create!(old_path: "#{prefix}-b", new_path: target, source: "manual", occurred_on: Date.current)
        end
      end
    rescue OpenBlog::Error => error
      error
    end
    pid = Timeout.timeout(5) { second_pid.pop }
    connection = ActiveRecord::Base.connection
    query = "SELECT wait_event_type FROM pg_stat_activity WHERE pid = #{Integer(pid)}"
    connection.cache do
      refute_equal "Lock", connection.select_value(query)
      start_second << true
      waiting = false
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
      until waiting || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        waiting = connection.uncached do
          connection.execute("SELECT pg_stat_clear_snapshot()")
          connection.select_value(query) == "Lock"
        end
        sleep 0.01 unless waiting
      end
      assert waiting, "The competing redirect must wait before reading the graph"
    end
    release << true
    first.value
    error = second.value
    assert_instance_of OpenBlog::Error::ValidationFailed, error
    assert_equal [ "redirect_to" ], error.details
    assert_equal 1, OpenBlog::Redirect.where("old_path LIKE ?", "#{prefix}%").count
  ensure
    release << true if release
    start_second << true if defined?(start_second) && start_second
    [ first, second ].compact.each { |thread| thread.join(5) }
    OpenBlog::Redirect.where("old_path LIKE ?", "#{prefix}%").delete_all if prefix
  end
  test "a competing SQLite writer returns a bounded typed refusal" do
    skip "SQLite writer lock" unless ActiveRecord::Base.connection.adapter_name == "SQLite"
    ready, release = Queue.new, Queue.new
    first = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        OpenBlog::RedirectTarget.synchronize do
          ready << true
          release.pop
        end
      end
    end
    Timeout.timeout(5) { ready.pop }
    second = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        previous = connection.select_value("PRAGMA busy_timeout")
        connection.execute("PRAGMA busy_timeout = 30")
        begin
          OpenBlog::RedirectTarget.synchronize { flunk "A second writer cannot enter the locked graph" }
        rescue OpenBlog::Error => error
          error
        ensure
          connection.execute("PRAGMA busy_timeout = #{Integer(previous)}")
        end
      end
    end
    error = Timeout.timeout(3) { second.value }
    assert_instance_of OpenBlog::Error::ValidationFailed, error
    assert_equal [ "redirects" ], error.details
  ensure
    release << true if release
    [ first, second ].compact.each { |thread| thread.join(5) }
  end
end
