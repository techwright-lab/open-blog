require_relative "test_helper"
require "rake"

class ApiTokenTaskTest < ActiveSupport::TestCase
  setup do
    @environment = %w[NAME SCOPES EXPIRES_AT].to_h { |key| [ key, ENV[key] ] }
    @rake = Rake.application
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load OpenBlog::Engine.root.join("lib/tasks/open_blog.rake")
  end

  teardown do
    @environment.each { |key, value| value ? ENV[key] = value : ENV.delete(key) }
    Rake.application = @rake
  end

  test "token task prints exactly one secret with requested settings" do
    ENV["NAME"] = "Night editor"
    ENV["SCOPES"] = "read,write"
    ENV["EXPIRES_AT"] = "2030-01-02T03:04:05Z"
    output, errors = capture_io { Rake::Task["open_blog:token"].invoke }
    assert_empty errors
    assert_match(/\Aob_[1-9A-HJ-NP-Za-km-z]{40}\n\z/, output)
    record = OpenBlog::ApiToken.authenticate(output.strip)
    assert_equal "Night editor", record.name
    assert_equal %w[read write], record.scopes
    assert_equal Time.utc(2030, 1, 2, 3, 4, 5), record.expires_at
  end
  test "installer issues one token and never replaces or reveals an existing secret" do
    hook = OpenBlog.config.authenticate
    OpenBlog.config.authenticate = nil
    output, = capture_io { Rake::Task["open_blog:install_token"].invoke }
    assert_match(/API token: ob_[1-9A-HJ-NP-Za-km-z]{40}/, output)
    assert_equal 1, OpenBlog::ApiToken.count
    token = OpenBlog::ApiToken.sole
    token.update!(revoked_at: Time.current)
    Rake::Task["open_blog:install_token"].reenable
    repeated, = capture_io { Rake::Task["open_blog:install_token"].invoke }
    refute_match(/ob_[1-9A-HJ-NP-Za-km-z]{40}/, repeated)
    assert_equal 1, OpenBlog::ApiToken.count
    assert_includes repeated, "existing"
  ensure
    OpenBlog.config.authenticate = hook
  end

  test "installer respects host authentication without issuing a token" do
    hook = OpenBlog.config.authenticate
    OpenBlog.config.authenticate = ->(_) { nil }
    assert_no_difference "OpenBlog::ApiToken.count" do
      output, = capture_io { Rake::Task["open_blog:install_token"].invoke }
      assert_includes output, "host authentication"
    end
  ensure
    OpenBlog.config.authenticate = hook
  end
end
