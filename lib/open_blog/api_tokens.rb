require_relative "api_tokens/grant"
require_relative "api_tokens/result"
require_relative "api_tokens/secret"

module OpenBlog
  module ApiTokens
    NAME_LENGTH = 1..100

    class << self
      def permissions(identity:)
        return unless identity.is_a?(String) && identity.match?(IDENTITY)
        grant = settings.policy&.grants_for(identity)
        grant if grant.is_a?(Grant)
      end

      def default_expires_at(now: Time.current)
        [ now + settings.default_lifetime, settings.max_lifetime && now + settings.max_lifetime ].compact.min
      end

      def list(identity:)
        authorize(identity) do |grant|
          Result.new(tokens: visible(identity, grant).order(created_at: :desc, id: :desc).to_a)
        end
      end

      def find(identity:, id:)
        authorize(identity) do |grant|
          token = visible(identity, grant).find_by(id: id)
          token ? Result.new(token: token) : failure(:not_found)
        end
      end

      def issue(identity:, name:, scopes:, expires_at:, now: Time.current)
        authorize(identity) do |grant|
          next failure(:unauthorized) unless grant.manage_own
          next failure(:tokens_inactive) if OpenBlog.config.authenticate
          name = name.strip if name.is_a?(String)
          scopes = scopes.map(&:to_s) if scopes.is_a?(Array)
          invalid = []
          invalid << "name" unless name.is_a?(String) && NAME_LENGTH.cover?(name.length)
          invalid << "scopes" unless valid_scopes?(scopes)
          next failure(:invalid, invalid) if invalid.any?
          next failure(:scope_not_allowed) unless (scopes - grant.scopes).empty?
          next failure(:expiry_invalid) unless valid_expiry?(expires_at, now)
          ApiToken.transaction { create_token(identity, name, scopes, expires_at) }
        end
      end

      def revoke(identity:, id:, now: Time.current)
        authorize(identity) do |grant|
          token = visible(identity, grant).find_by(id: id)
          next failure(:not_found) unless token
          ApiToken.transaction do
            if ApiToken.where(id: token.id, revoked_at: nil).update_all(revoked_at: now, updated_at: now) == 1
              record_event(token, identity, "revoked", {})
            end
            Result.new(token: token.reload)
          end
        end
      end

      def rotate(identity:, id:, grace: nil, now: Time.current)
        authorize(identity) do |grant|
          next failure(:tokens_inactive) if OpenBlog.config.authenticate
          token = visible(identity, grant).find_by(id: id)
          next failure(:not_found) unless token
          next failure(:not_rotatable) if token.creator_identity.nil?
          next failure(:unauthorized) unless token.creator_identity == identity && grant.manage_own
          next failure(:grace_invalid) unless grace.nil? || valid_grace?(grace)
          ApiToken.transaction(requires_new: true) do
            rotate_locked(ApiToken.lock.find(token.id), identity, grant, grace, now)
          end || failure(:already_rotated)
        end
      end

      private

      def settings
        OpenBlog.config.api_tokens
      end

      def authorize(identity)
        grant = permissions(identity: identity)
        return failure(:unauthorized) unless grant && (grant.manage_own || grant.manage_all)
        yield grant
      end

      def visible(identity, grant)
        grant.manage_all ? ApiToken.all : ApiToken.where(creator_identity: identity)
      end

      def failure(error, details = [])
        Result.new(error: error, details: details)
      end

      def valid_scopes?(scopes)
        scopes.is_a?(Array) && scopes.any? && scopes.uniq.size == scopes.size && (scopes - SCOPES).empty?
      end

      def valid_expiry?(expires_at, now)
        max = settings.max_lifetime
        return !settings.require_expiry && max.nil? if expires_at.nil?
        return false unless expires_at.is_a?(Time) || expires_at.is_a?(DateTime)
        expires_at > now && (max.nil? || expires_at <= now + max)
      end

      def valid_grace?(grace)
        (grace.is_a?(Numeric) || grace.is_a?(ActiveSupport::Duration)) && grace.to_f.finite? &&
          grace.to_f.positive? && grace.to_f <= settings.max_grace.to_f
      end

      def create_token(identity, name, scopes, expires_at, **details)
        token, secret = ApiToken.generate(name: name, scopes: scopes, expires_at: expires_at, creator_identity: identity)
        record_event(token, identity, "issued", { scopes: scopes, expires_at: expires_at&.iso8601, **details })
        Result.new(token: token, secret: Secret.new(secret))
      end

      # sqlite ignores FOR UPDATE, so the guarded update_all is what keeps one successor
      # per token. Losing that race raises Rollback, which needs the requires_new savepoint.
      def rotate_locked(old, identity, grant, grace, now)
        return failure(:already_rotated) if old.successor_id
        return failure(:not_rotatable) unless old.revoked_at.nil? && (old.expires_at.nil? || old.expires_at > now)
        return failure(:scope_not_allowed) unless (old.scopes - grant.scopes).empty?

        cutoff = grace ? [ old.expires_at, now + grace ].compact.min : now
        replacement = create_token(identity, old.name, old.scopes, default_expires_at(now: now), predecessor_id: old.id)
        changes = grace ? { expires_at: cutoff } : { revoked_at: now }
        claimed = begin
          ApiToken.where(id: old.id, successor_id: nil, revoked_at: nil)
            .update_all(changes.merge(successor_id: replacement.token.id, updated_at: now))
        rescue ActiveRecord::RecordNotUnique
          0
        end
        raise ActiveRecord::Rollback unless claimed == 1

        record_event(old, identity, "rotated", { successor_id: replacement.token.id, old_expires_at: old.expires_at&.iso8601,
          new_cutoff: cutoff.iso8601, revoked: grace.nil? })
        replacement
      end

      def record_event(token, identity, action, details)
        ApiTokenEvent.create!(api_token: token, actor_identity: identity, action: action, details: details)
      end
    end
  end
end
