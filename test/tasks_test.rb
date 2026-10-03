require_relative "test_helper"
require "rake"
require "minitest/mock"

class TasksTest < ActiveSupport::TestCase
  setup do
    @previous_rake = Rake.application
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load File.expand_path("../lib/tasks/open_blog.rake", __dir__)
  end

  teardown do
    Rake.application = @previous_rake
  end

  test "doctor reports every result and exits unsuccessfully for errors" do
    checks = [ { name: "Configuration", status: "ok", message: "Ready" },
      { name: "Policy pages", status: "warning", message: "Add an editorial page" },
      { name: "Migrations", status: "error", message: "Run db:migrate" } ]
    OpenBlog::Doctor.stub(:run, checks) do
      output, = capture_io do
        error = assert_raises(SystemExit) { Rake::Task["open_blog:doctor"].invoke }
        assert_equal 1, error.status
      end
      checks.each do |check|
        assert_includes output, check[:name]
        assert_includes output, check[:status]
        assert_includes output, check[:message]
      end
    end
  end

  test "doctor warnings are reported without failing the task" do
    OpenBlog::Doctor.stub(:run, [ { name: "Authentication", status: "warning", message: "API token: none" } ]) do
      output, = capture_io { Rake::Task["open_blog:doctor"].invoke }
      assert_includes output, "API token: none"
    end
  end

  test "sample task shows the resulting article location" do
    post = Struct.new(:path).new("/journal/welcome")
    OpenBlog::Sample.stub(:call, post) do
      output, = capture_io { Rake::Task["open_blog:sample"].invoke }
      assert_includes output, "/journal/welcome"
    end
  end

  test "stylesheet task forwards an explicit output path" do
    previous = ENV["OUT"]
    ENV["OUT"] = "/tmp/blog theme.css"
    build = ->(**options) { assert_equal({ path: ENV["OUT"] }, options); options[:path] }
    OpenBlog::BuildCss.stub(:write, build) do
      output, = capture_io { Rake::Task["open_blog:build_css"].invoke }
      assert_includes output, ENV["OUT"]
    end
  ensure
    ENV["OUT"] = previous
  end
end
