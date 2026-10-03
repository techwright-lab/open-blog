require_relative "test_helper"
require "minitest/mock"

class ApiTokenTest < ActiveSupport::TestCase
  test "generation persists only digest and prefix and returns a unique secret" do
    token, secret = OpenBlog::ApiToken.generate(name: "Editor")
    assert_match(/\Aob_[1-9A-HJ-NP-Za-km-z]{40}\z/, secret)
    assert_equal Digest::SHA256.hexdigest(secret), token.token_digest
    assert_equal secret[0, 8], token.token_prefix
    assert_equal %w[read write publish], token.scopes
    refute_includes token.attributes.values, secret
    refute_equal secret, OpenBlog::ApiToken.generate(name: "Editor").last
  end

  test "authentication updates only active matching tokens" do
    token, secret = OpenBlog::ApiToken.generate(name: "Reader", scopes: [ "read" ])
    assert_nil token.last_used_at
    assert_equal token, OpenBlog::ApiToken.authenticate(secret)
    assert token.reload.last_used_at
    timestamp = token.last_used_at
    token.update!(revoked_at: Time.current)
    assert_nil OpenBlog::ApiToken.authenticate(secret)
    assert_equal timestamp, token.reload.last_used_at
    token.update!(revoked_at: nil, expires_at: 1.second.ago)
    assert_nil OpenBlog::ApiToken.authenticate(secret)
    assert_equal timestamp, token.reload.last_used_at
    assert_nil OpenBlog::ApiToken.authenticate("ob_" + "x" * 40)
    assert_nil OpenBlog::ApiToken.authenticate(nil)
  end

  test "digest comparison uses constant time comparison" do
    token, secret = OpenBlog::ApiToken.generate(name: "Editor")
    calls = []
    compare = ActiveSupport::SecurityUtils.method(:secure_compare)
    ActiveSupport::SecurityUtils.stub(:secure_compare, ->(a, b) { calls << [ a, b ]; compare.call(a, b) }) do
      assert_equal token, OpenBlog::ApiToken.authenticate(secret)
    end
    assert_equal [ [ token.token_digest, Digest::SHA256.hexdigest(secret) ] ], calls
  end

  test "invalid scopes and blank names are refused while an empty scope list is retained" do
    assert_raises(ActiveRecord::RecordInvalid) { OpenBlog::ApiToken.generate(name: " ") }
    assert_raises(ActiveRecord::RecordInvalid) { OpenBlog::ApiToken.generate(name: "Editor", scopes: [ "admin" ]) }
    assert_equal [], OpenBlog::ApiToken.generate(name: "Observer", scopes: []).first.scopes
  end
end
