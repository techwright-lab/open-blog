require_relative "test_helper"
require "open3"
require "tmpdir"
require "bundler"

class ApiTokenBootTest < ActiveSupport::TestCase
  test "grants load from an initializer before engine models are autoloadable" do
    root = File.expand_path("..", __dir__)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "grants.yml")
      File.write(path, "api_tokens:\n  grants:\n    \"user:ada\":\n      manage: [own]\n      scopes: [read]\n")
      script = <<~RUBY
        require File.join(ENV.fetch("OPEN_BLOG_ROOT"), "test/dummy/config/application")
        Rails.application.config.before_initialize do
          puts OpenBlog::ApiTokens::YamlGrants.load(ENV.fetch("OPEN_BLOG_GRANTS")).grants_for("user:ada").to_h.to_json
        end
        Rails.application.initialize!
      RUBY
      env = { "OPEN_BLOG_ROOT" => root, "OPEN_BLOG_GRANTS" => path, "RAILS_ENV" => "test", "DB" => "sqlite" }
      env["BUNDLE_GEMFILE"] = ENV["BUNDLE_GEMFILE"] if ENV["BUNDLE_GEMFILE"]
      stdout, stderr, status = Bundler.with_unbundled_env do
        Open3.capture3(env, Gem.ruby, "-rbundler/setup", "-Ilib", "-e", script, chdir: root)
      end
      assert_predicate status, :success?, stderr
      assert_equal({ "manage_own" => true, "manage_all" => false, "scopes" => [ "read" ] }, JSON.parse(stdout.lines.last))
    end
  end
end
