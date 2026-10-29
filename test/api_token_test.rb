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

  test "invalid scopes and blank names are refused" do
    assert_raises(ActiveRecord::RecordInvalid) { OpenBlog::ApiToken.generate(name: " ") }
    assert_raises(ActiveRecord::RecordInvalid) { OpenBlog::ApiToken.generate(name: "Editor", scopes: [ "admin" ]) }
  end

  test "rejects empty scopes" do
    assert_raises(ActiveRecord::RecordInvalid) { OpenBlog::ApiToken.generate(name: "x", scopes: []) }
  end

  test "rejects repeated scopes" do
    assert_raises(ActiveRecord::RecordInvalid) { OpenBlog::ApiToken.generate(name: "x", scopes: %w[read read]) }
  end

  test "records creator identity" do
    record, = OpenBlog::ApiToken.generate(name: "x", scopes: %w[read], creator_identity: "admin:1")
    assert_equal "admin:1", record.reload.creator_identity
  end

  test "stops authenticating at exactly expires_at" do
    expires_at = Time.zone.local(2030, 1, 1, 12)
    _, secret = OpenBlog::ApiToken.generate(name: "x", scopes: %w[read], expires_at: expires_at)
    travel_to(expires_at - 1.second) { assert OpenBlog::ApiToken.authenticate(secret) }
    travel_to(expires_at) { assert_nil OpenBlog::ApiToken.authenticate(secret) }
  end

  test "status reports revoked over expired" do
    record, = OpenBlog::ApiToken.generate(name: "x", scopes: %w[read], expires_at: 1.day.from_now)
    assert_equal :active, record.status
    record.update!(expires_at: 1.second.ago)
    assert_equal :expired, record.status
    record.update!(revoked_at: Time.current)
    assert_equal :revoked, record.status
  end

  test "successor id is unique" do
    successor, = OpenBlog::ApiToken.generate(name: "new", scopes: %w[read])
    first, = OpenBlog::ApiToken.generate(name: "a", scopes: %w[read])
    second, = OpenBlog::ApiToken.generate(name: "b", scopes: %w[read])
    first.update!(successor: successor)
    assert_equal first, successor.predecessor
    assert_raises(ActiveRecord::RecordNotUnique) { second.update!(successor: successor) }
  end

  test "foreign keys match the token primary key type" do
    id_type = OpenBlog::ApiToken.columns_hash["id"].sql_type
    expected = id_type == "uuid" ? "uuid" : "bigint"
    assert_equal expected, OpenBlog::ApiToken.columns_hash["successor_id"].sql_type
    assert_equal expected, OpenBlog::ApiTokenEvent.columns_hash["api_token_id"].sql_type
  end

  test "inspect omits digest" do
    record, = OpenBlog::ApiToken.generate(name: "x", scopes: %w[read])
    refute_includes record.inspect, record.token_digest
  end

  test "events validate action and actor" do
    record, = OpenBlog::ApiToken.generate(name: "x", scopes: %w[read])
    assert record.events.create!(action: "issued", actor_identity: "admin:1").persisted?
    refute record.events.build(action: "deleted", actor_identity: "admin:1").valid?
    refute record.events.build(action: "issued", actor_identity: "").valid?
    assert_raises(ActiveRecord::DeleteRestrictionError) { record.destroy }
  end
end
