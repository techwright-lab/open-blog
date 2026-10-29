require_relative "test_helper"
require "tmpdir"

class ApiTokenPolicyTest < ActiveSupport::TestCase
  def policy_for(yaml)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "grants.yml")
      File.write(path, yaml)
      OpenBlog::ApiTokens::YamlGrants.load(path)
    end
  end

  def assert_rejected(yaml)
    assert_raises(OpenBlog::ConfigurationError) { policy_for(yaml) }
  end

  test "loads grants" do
    policy = policy_for(<<~YAML)
      api_tokens:
        grants:
          "user:ada":
            manage: [own]
            scopes: [read, write]
    YAML
    grant = OpenBlog::ApiTokens::Grant.new(manage_own: true, manage_all: false, scopes: %w[read write])
    assert_equal grant, policy.grants_for("user:ada")
    assert_predicate policy.grants_for("user:ada").scopes, :frozen?
  end

  test "unknown identity has no grant" do
    policy = policy_for("api_tokens:\n  grants:\n    \"user:ada\":\n      manage: [all]\n      scopes: [read]\n")
    assert_nil policy.grants_for("user:bob")
  end

  test "missing file grants nothing" do
    assert_nil OpenBlog::ApiTokens::YamlGrants.load("/nonexistent/grants.yml").grants_for("user:ada")
  end

  test "empty grants grant nothing" do
    assert_nil policy_for("api_tokens:\n  grants: ~\n").grants_for("user:ada")
    assert_nil policy_for("api_tokens:\n  grants: {}\n").grants_for("user:ada")
  end

  test "rejects unknown top-level keys" do
    assert_rejected "other: {}\n"
  end

  test "rejects unknown api_tokens keys" do
    assert_rejected "api_tokens:\n  extra: 1\n"
  end

  test "rejects malformed identity keys" do
    assert_rejected "api_tokens:\n  grants:\n    \"Ada Lovelace\":\n      manage: [own]\n"
  end

  test "rejects unknown grant keys" do
    assert_rejected "api_tokens:\n  grants:\n    \"user:ada\":\n      admin: true\n"
  end

  test "rejects unknown manage values" do
    assert_rejected "api_tokens:\n  grants:\n    \"user:ada\":\n      manage: [everything]\n"
  end

  test "rejects unknown scopes" do
    assert_rejected "api_tokens:\n  grants:\n    \"user:ada\":\n      scopes: [root]\n"
  end

  test "rejects aliases" do
    assert_rejected "api_tokens:\n  grants:\n    \"user:ada\": &g\n      scopes: [read]\n    \"user:bob\": *g\n"
  end

  test "defaults" do
    settings = OpenBlog::Configuration.new.api_tokens
    assert_equal 90.days, settings.default_lifetime
    assert_equal false, settings.require_expiry
    assert_nil settings.max_lifetime
    assert_equal 24.hours, settings.max_grace
    assert_nil settings.identity
    assert_nil settings.policy
  end

  test "rejects zero max_grace" do
    config = OpenBlog::Configuration.new
    config.api_tokens.max_grace = 0
    assert_raises(OpenBlog::ConfigurationError) { config.validate_structure! }
  end

  test "rejects max_lifetime below default_lifetime" do
    config = OpenBlog::Configuration.new
    config.api_tokens.max_lifetime = 30.days
    assert_raises(OpenBlog::ConfigurationError) { config.validate_structure! }
  end

  test "rejects policy without grants_for" do
    config = OpenBlog::Configuration.new
    config.api_tokens.policy = Object.new
    assert_raises(OpenBlog::ConfigurationError) { config.validate_structure! }
  end

  test "rejects identity hook with wrong arity" do
    assert_raises(OpenBlog::ConfigurationError) { OpenBlog::Configuration.new.api_tokens.identity = ->(a, b) { } }
  end

  test "accepts a valid configuration" do
    config = OpenBlog::Configuration.new
    config.api_tokens.identity = ->(request) { "user:#{request}" }
    config.api_tokens.policy = OpenBlog::ApiTokens::YamlGrants.load("/nonexistent")
    config.api_tokens.max_lifetime = 180.days
    assert_same config, config.validate_structure!
  end
end
