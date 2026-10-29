require_relative "test_helper"
require "minitest/mock"

class ApiTokenOperationsTest < ActiveSupport::TestCase
  Policy = Struct.new(:grants) do
    def grants_for(identity)
      grants[identity]
    end
  end

  OPS = OpenBlog::ApiTokens
  ADA = "user:ada"
  BOB = "user:bob"
  AUDITOR = "user:auditor"
  BOTH = "user:both"

  setup do
    @settings = OpenBlog.config.api_tokens
    @saved = %i[policy default_lifetime require_expiry max_lifetime max_grace].to_h { |key| [ key, @settings.public_send(key) ] }
    @saved_authenticate = OpenBlog.config.authenticate
    OpenBlog.config.authenticate = nil
    @grants = {
      ADA => grant(own: true, scopes: %w[read write]),
      BOB => grant(own: true, scopes: %w[read write publish]),
      AUDITOR => grant(all: true, scopes: %w[read]),
      BOTH => grant(own: true, all: true, scopes: %w[read write])
    }
    @settings.policy = Policy.new(@grants)
    @now = Time.current.change(usec: 0)
  end

  teardown do
    @saved.each { |key, value| @settings.public_send(:"#{key}=", value) }
    OpenBlog.config.authenticate = @saved_authenticate
  end

  def grant(own: false, all: false, scopes: [])
    OpenBlog::ApiTokens::Grant.new(manage_own: own, manage_all: all, scopes: scopes)
  end

  def issue(identity = ADA, name: "Deploy", scopes: %w[read], expires_at: @now + 30.days, now: @now)
    OPS.issue(identity: identity, name: name, scopes: scopes, expires_at: expires_at, now: now)
  end

  def issued(identity = ADA, **options)
    result = issue(identity, **options)
    assert result.success?, result.error.inspect
    result
  end

  test "secret filters every rendering" do
    secret = OpenBlog::ApiTokens::Secret.new("ob_secretvalue")
    assert_equal "ob_secretvalue", secret.reveal
    assert_equal "[FILTERED]", secret.inspect
    assert_equal "[FILTERED]", secret.to_s
    assert_equal "[FILTERED]", secret.as_json
    assert_equal '"[FILTERED]"', secret.to_json
    assert_equal '{"secret":"[FILTERED]"}', { secret: secret }.to_json
    assert_equal '"[FILTERED]"', JSON.generate(secret)
    refute_includes "#{secret}", "ob_secretvalue"
  end

  test "result defaults and success" do
    result = OpenBlog::ApiTokens::Result.new
    assert_predicate result, :success?
    assert_nil result.token
    assert_equal [], result.tokens
    assert_nil result.secret
    assert_nil result.error
    assert_equal [], result.details
    refute_predicate OpenBlog::ApiTokens::Result.new(error: :invalid), :success?
  end

  test "permissions returns the grant only for well-formed identities" do
    assert_equal @grants[ADA], OPS.permissions(identity: ADA)
    assert_nil OPS.permissions(identity: "user:nobody")
    assert_nil OPS.permissions(identity: "Ada Lovelace")
    assert_nil OPS.permissions(identity: nil)
    @settings.policy = nil
    assert_nil OPS.permissions(identity: ADA)
  end

  test "issue persists metadata, returns a filtered secret, and writes one issued event" do
    result = issued(name: "  Deploy  ", scopes: %w[read write])
    token = result.token
    secret = result.secret.reveal
    assert_equal token, OpenBlog::ApiToken.authenticate(secret)
    assert_equal "Deploy", token.name
    assert_equal %w[read write], token.scopes
    assert_equal ADA, token.creator_identity
    assert_equal @now + 30.days, token.expires_at
    refute_includes result.inspect, secret
    refute_includes result.to_h.to_s, secret
    refute_includes token.inspect, secret
    assert_equal 1, token.events.count
    event = token.events.sole
    assert_equal "issued", event.action
    assert_equal ADA, event.actor_identity
    assert_equal({ "scopes" => %w[read write], "expires_at" => (@now + 30.days).iso8601 }, event.details)
    refute_includes OpenBlog::ApiTokenEvent.pluck(:details).to_json, secret
  end

  test "unauthorized without a usable grant" do
    @grants["user:none"] = grant(scopes: %w[read])
    [ "user:none", "user:missing", "Ada Lovelace", nil ].each do |identity|
      assert_equal :unauthorized, issue(identity).error
      assert_equal :unauthorized, OPS.list(identity: identity).error
    end
    @settings.policy = nil
    assert_equal :unauthorized, issue.error
    assert_equal :unauthorized, OPS.list(identity: ADA).error
    assert_equal 0, OpenBlog::ApiToken.count
  end

  test "manage all without manage own cannot issue" do
    assert_equal :unauthorized, issue(AUDITOR).error
    assert_equal 0, OpenBlog::ApiToken.count
  end

  test "issue validates name and scopes" do
    assert_equal [ :invalid, [ "name" ] ], issue(name: "   ").then { |result| [ result.error, result.details ] }
    assert_equal [ "name" ], issue(name: "x" * 101).details
    assert issue(name: "x" * 100).success?
    assert_equal [ "name" ], issue(name: nil).details
    assert_equal [ "scopes" ], issue(scopes: []).details
    assert_equal [ "scopes" ], issue(scopes: %w[read read]).details
    assert_equal [ "scopes" ], issue(scopes: %w[admin]).details
    assert_equal [ "scopes" ], issue(scopes: "read").details
    assert_equal %w[name scopes], issue(name: "", scopes: []).details
    assert_equal 1, OpenBlog::ApiToken.count
  end

  test "requested scopes must be within the ceiling" do
    assert_equal :scope_not_allowed, issue(scopes: %w[read publish]).error
    assert issued(BOB, scopes: %w[publish]).success?
  end

  test "expiry rules" do
    assert issue(expires_at: nil).success?
    assert_equal :expiry_invalid, issue(expires_at: @now).error
    assert_equal :expiry_invalid, issue(expires_at: @now - 1.day).error
    assert_equal :expiry_invalid, issue(expires_at: "tomorrow").error
    @settings.require_expiry = true
    assert_equal :expiry_invalid, issue(expires_at: nil).error
    @settings.require_expiry = false
    @settings.max_lifetime = 180.days
    assert_equal :expiry_invalid, issue(expires_at: nil).error
    assert_equal :expiry_invalid, issue(expires_at: @now + 180.days + 1.second).error
    assert issue(expires_at: @now + 180.days).success?
  end

  test "default expiry" do
    assert_equal @now + 90.days, OPS.default_expires_at(now: @now)
    @settings.default_lifetime = 7.days
    assert_equal @now + 7.days, OPS.default_expires_at(now: @now)
  end

  test "own only sees only own tokens and cannot reach others by id" do
    mine = issued(ADA).token
    theirs = issued(BOB).token
    ownerless, = OpenBlog::ApiToken.generate(name: "CLI")
    assert_equal [ mine ], OPS.list(identity: ADA).tokens
    assert_equal mine, OPS.find(identity: ADA, id: mine.id).token
    [ theirs, ownerless ].each do |other|
      assert_equal :not_found, OPS.find(identity: ADA, id: other.id).error
      assert_equal :not_found, OPS.revoke(identity: ADA, id: other.id).error
      assert_equal :not_found, OPS.rotate(identity: ADA, id: other.id).error
    end
    assert_equal :not_found, OPS.find(identity: ADA, id: "nonexistent").error
    assert_equal :not_found, OPS.revoke(identity: ADA, id: 0).error
    assert_nil theirs.reload.revoked_at
    assert_nil ownerless.reload.revoked_at
  end

  test "manage all lists and revokes others but cannot rotate them" do
    older = issued(ADA, now: @now - 1.hour).token
    older.update_columns(created_at: @now - 1.hour)
    newer = issued(BOB).token
    ownerless, = OpenBlog::ApiToken.generate(name: "CLI")
    ownerless.update_columns(created_at: @now - 2.hours)
    assert_equal [ newer, older, ownerless ], OPS.list(identity: AUDITOR).tokens
    assert_equal older, OPS.find(identity: AUDITOR, id: older.id).token
    assert_equal :unauthorized, OPS.rotate(identity: AUDITOR, id: older.id).error
    assert_equal :unauthorized, OPS.rotate(identity: BOTH, id: older.id).error
    assert_equal :not_rotatable, OPS.rotate(identity: AUDITOR, id: ownerless.id).error
    assert_equal :not_rotatable, OPS.rotate(identity: BOTH, id: ownerless.id).error

    result = OPS.revoke(identity: AUDITOR, id: older.id, now: @now)
    assert result.success?
    assert_equal @now, older.reload.revoked_at
    assert_equal AUDITOR, older.events.find_by!(action: "revoked").actor_identity
    assert OPS.revoke(identity: AUDITOR, id: ownerless.id, now: @now).success?
    assert_equal :revoked, ownerless.reload.status
    assert_equal [ "revoked" ], ownerless.events.pluck(:action)
  end

  test "repeat revoke succeeds without changing revoked_at or adding an event" do
    token = issued.token
    assert OPS.revoke(identity: ADA, id: token.id, now: @now).success?
    result = OPS.revoke(identity: ADA, id: token.id, now: @now + 1.hour)
    assert result.success?
    assert_equal @now, result.token.revoked_at
    assert_equal @now, token.reload.revoked_at
    revoked = token.events.where(action: "revoked")
    assert_equal 1, revoked.count
    assert_equal({}, revoked.sole.details)
  end

  test "immediate rotation revokes the old token and issues a replacement" do
    old = issued(scopes: %w[read write], expires_at: @now + 10.days).token
    events_before = OpenBlog::ApiTokenEvent.count
    result = OPS.rotate(identity: ADA, id: old.id, now: @now)
    assert result.success?, result.error.inspect
    replacement = result.token
    secret = result.secret.reveal
    old.reload
    assert_equal @now, old.revoked_at
    assert_equal @now + 10.days, old.expires_at
    assert_equal replacement, old.successor
    assert_equal old, replacement.predecessor
    assert_equal [ "Deploy", %w[read write], ADA ], [ replacement.name, replacement.scopes, replacement.creator_identity ]
    assert_equal @now + 90.days, replacement.expires_at
    assert_equal replacement, OpenBlog::ApiToken.authenticate(secret)
    assert_equal events_before + 2, OpenBlog::ApiTokenEvent.count
    rotated = old.events.find_by!(action: "rotated")
    assert_equal ADA, rotated.actor_identity
    assert_equal({ "successor_id" => replacement.id, "old_expires_at" => (@now + 10.days).iso8601,
      "new_cutoff" => @now.iso8601, "revoked" => true }, rotated.details)
    issued_event = replacement.events.sole
    assert_equal "issued", issued_event.action
    assert_equal({ "scopes" => %w[read write], "expires_at" => (@now + 90.days).iso8601, "predecessor_id" => old.id },
      issued_event.details)
    refute_includes result.inspect, secret
    refute_includes OpenBlog::ApiTokenEvent.pluck(:details).to_json, secret
  end

  test "replacement expiry is capped by max lifetime" do
    @settings.default_lifetime = 30.days
    @settings.max_lifetime = 30.days
    old = issued(expires_at: @now + 1.day).token
    assert_equal @now + 30.days, OPS.rotate(identity: ADA, id: old.id, now: @now).token.expires_at
  end

  test "grace rotation sets a bounded cutoff that never extends an earlier expiry" do
    old = issued(expires_at: @now + 10.days).token
    result = OPS.rotate(identity: ADA, id: old.id, grace: 2.hours, now: @now)
    assert result.success?
    old.reload
    assert_nil old.revoked_at
    assert_equal @now + 2.hours, old.expires_at
    assert_equal({ "successor_id" => result.token.id, "old_expires_at" => (@now + 10.days).iso8601,
      "new_cutoff" => (@now + 2.hours).iso8601, "revoked" => false }, old.events.find_by!(action: "rotated").details)

    soon = issued(expires_at: @now + 1.hour).token
    assert OPS.rotate(identity: ADA, id: soon.id, grace: 5.hours, now: @now).success?
    assert_equal @now + 1.hour, soon.reload.expires_at

    forever = issued(expires_at: nil).token
    assert OPS.rotate(identity: ADA, id: forever.id, grace: 3.hours, now: @now).success?
    assert_equal @now + 3.hours, forever.reload.expires_at
  end

  test "grace must be positive and at most max grace" do
    old = issued.token
    [ 0, -1, 24.hours + 1.second, "1 hour", Float::INFINITY ].each do |grace|
      assert_equal :grace_invalid, OPS.rotate(identity: ADA, id: old.id, grace: grace, now: @now).error
    end
    assert_nil old.reload.successor_id
    assert OPS.rotate(identity: ADA, id: old.id, grace: 24.hours, now: @now).success?
  end

  test "token in grace can still be revoked immediately" do
    old = issued.token
    assert OPS.rotate(identity: ADA, id: old.id, grace: 1.hour, now: @now).success?
    assert OPS.revoke(identity: ADA, id: old.id, now: @now + 1.minute).success?
    assert_equal @now + 1.minute, old.reload.revoked_at
  end

  test "second rotation returns already_rotated" do
    old = issued.token
    assert OPS.rotate(identity: ADA, id: old.id, grace: 1.hour, now: @now).success?
    count = OpenBlog::ApiToken.count
    assert_equal :already_rotated, OPS.rotate(identity: ADA, id: old.id, now: @now).error
    immediate = issued.token
    assert OPS.rotate(identity: ADA, id: immediate.id, now: @now).success?
    assert_equal :already_rotated, OPS.rotate(identity: ADA, id: immediate.id, now: @now).error
    assert_equal count + 2, OpenBlog::ApiToken.count
  end

  test "rotation from a stale read still yields one successor" do
    old = issued.token
    stale = OpenBlog::ApiToken.find(old.id)
    first = OPS.rotate(identity: ADA, id: old.id, grace: 1.hour, now: @now)
    assert first.success?
    count = OpenBlog::ApiToken.count
    events = OpenBlog::ApiTokenEvent.count
    lock = Object.new
    lock.define_singleton_method(:find) { |_id| stale }
    result = OpenBlog::ApiToken.stub(:lock, lock) { OPS.rotate(identity: ADA, id: old.id, now: @now) }
    assert_equal :already_rotated, result.error
    assert_equal first.token, old.reload.successor
    assert_nil old.revoked_at
    assert_equal [ count, events ], [ OpenBlog::ApiToken.count, OpenBlog::ApiTokenEvent.count ]
  end

  test "stale read inside a joinable host transaction leaves no orphan replacement" do
    old = issued.token
    stale = OpenBlog::ApiToken.find(old.id)
    first = OPS.rotate(identity: ADA, id: old.id, grace: 1.hour, now: @now)
    count = OpenBlog::ApiToken.count
    events = OpenBlog::ApiTokenEvent.count
    lock = Object.new
    lock.define_singleton_method(:find) { |_id| stale }
    result = ActiveRecord::Base.transaction do
      OpenBlog::ApiToken.stub(:lock, lock) { OPS.rotate(identity: ADA, id: old.id, now: @now) }
    end
    assert_equal :already_rotated, result.error
    assert_equal first.token, old.reload.successor
    assert_equal [ count, events ], [ OpenBlog::ApiToken.count, OpenBlog::ApiTokenEvent.count ]
  end

  test "successor index violation returns already_rotated and rolls back" do
    taken = issued.token
    taken_successor = OPS.rotate(identity: ADA, id: taken.id, now: @now).token
    old = issued.token
    count = OpenBlog::ApiToken.count
    events = OpenBlog::ApiTokenEvent.count
    reuse_successor = ->(**) { [ taken_successor, "ob_#{'1' * 40}" ] }
    result = OpenBlog::ApiToken.stub(:generate, reuse_successor) { OPS.rotate(identity: ADA, id: old.id, now: @now) }
    assert_equal :already_rotated, result.error
    assert_equal [ count, events ], [ OpenBlog::ApiToken.count, OpenBlog::ApiTokenEvent.count ]
    old.reload
    assert_nil old.successor_id
    assert_nil old.revoked_at
    assert_equal taken_successor, taken.reload.successor
  end

  test "other uniqueness errors during rotation propagate and roll back" do
    old = issued.token
    count = OpenBlog::ApiToken.count
    raise_unique = ->(*) { raise ActiveRecord::RecordNotUnique, "duplicate" }
    OpenBlog::ApiTokenEvent.stub(:create!, raise_unique) do
      assert_raises(ActiveRecord::RecordNotUnique) { OPS.rotate(identity: ADA, id: old.id, now: @now) }
    end
    assert_equal count, OpenBlog::ApiToken.count
    assert_nil old.reload.successor_id
  end

  test "rotating a replacement leaves the predecessor cutoff unchanged" do
    first = issued(expires_at: @now + 10.days).token
    second = OPS.rotate(identity: ADA, id: first.id, grace: 2.hours, now: @now).token
    third = OPS.rotate(identity: ADA, id: second.id, grace: 20.hours, now: @now + 1.hour)
    assert third.success?
    assert_equal @now + 2.hours, first.reload.expires_at
    assert_nil first.revoked_at
    assert_equal @now + 21.hours, second.reload.expires_at
  end

  test "revoked, expired, and ownerless tokens are not rotatable" do
    revoked = issued.token
    OPS.revoke(identity: ADA, id: revoked.id, now: @now)
    expired = issued(expires_at: @now + 1.minute).token
    assert_equal :not_rotatable, OPS.rotate(identity: ADA, id: revoked.id, now: @now).error
    assert_equal :not_rotatable, OPS.rotate(identity: ADA, id: expired.id, now: @now + 1.minute).error
    assert_nil expired.reload.successor_id
    ownerless, = OpenBlog::ApiToken.generate(name: "CLI")
    assert_equal :not_rotatable, OPS.rotate(identity: BOTH, id: ownerless.id, now: @now).error
    assert_nil ownerless.reload.successor_id
  end

  test "rotation is blocked when the scope ceiling shrank" do
    old = issued(scopes: %w[read write]).token
    @grants[ADA] = grant(own: true, scopes: %w[read])
    assert_equal :scope_not_allowed, OPS.rotate(identity: ADA, id: old.id, now: @now).error
    assert_nil old.reload.successor_id
    assert_nil old.revoked_at
  end

  test "host authenticate hook makes issue and rotate inactive before any write" do
    old = issued.token
    OpenBlog.config.authenticate = ->(_) { nil }
    count = OpenBlog::ApiToken.count
    assert_equal :tokens_inactive, issue.error
    assert_equal :tokens_inactive, OPS.rotate(identity: ADA, id: old.id, now: @now).error
    assert_equal count, OpenBlog::ApiToken.count
    assert_nil old.reload.successor_id
    assert OPS.list(identity: ADA).success?
    assert OPS.revoke(identity: ADA, id: old.id, now: @now).success?
  end

  test "removed grant denies the next call while the token still authenticates" do
    result = issued
    token = result.token
    @grants.delete(ADA)
    assert_equal :unauthorized, OPS.list(identity: ADA).error
    assert_equal :unauthorized, OPS.find(identity: ADA, id: token.id).error
    assert_equal :unauthorized, OPS.revoke(identity: ADA, id: token.id).error
    assert_equal :unauthorized, OPS.rotate(identity: ADA, id: token.id).error
    assert_equal :unauthorized, issue.error
    assert_equal token, OpenBlog::ApiToken.authenticate(result.secret.reveal)
  end

  test "event write failure rolls back the mutation" do
    old = issued.token
    count = OpenBlog::ApiToken.count
    failing = ->(*) { raise ActiveRecord::RecordInvalid }
    OpenBlog::ApiTokenEvent.stub(:create!, failing) do
      assert_raises(ActiveRecord::RecordInvalid) { issue }
      assert_raises(ActiveRecord::RecordInvalid) { OPS.revoke(identity: ADA, id: old.id, now: @now) }
      assert_raises(ActiveRecord::RecordInvalid) { OPS.rotate(identity: ADA, id: old.id, now: @now) }
    end
    assert_equal count, OpenBlog::ApiToken.count
    old.reload
    assert_nil old.revoked_at
    assert_nil old.successor_id
    assert_equal 1, OpenBlog::ApiTokenEvent.count
  end
end
