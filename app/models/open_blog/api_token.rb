require "digest"
require "active_support/core_ext/securerandom"

module OpenBlog
  class ApiToken < ApplicationRecord
    SCOPES = ApiTokens::SCOPES
    scope :active, -> { where(revoked_at: nil).where("expires_at IS NULL OR expires_at > ?", Time.current) }

    self.filter_attributes += %w[token_digest]

    belongs_to :successor, class_name: "OpenBlog::ApiToken", optional: true
    has_one :predecessor, class_name: "OpenBlog::ApiToken", foreign_key: :successor_id, inverse_of: :successor
    has_many :events, class_name: "OpenBlog::ApiTokenEvent", dependent: :restrict_with_exception

    validates :name, presence: true
    validates :token_digest, presence: true, uniqueness: true, format: { with: /\A[0-9a-f]{64}\z/ }
    validates :token_prefix, length: { is: 8 }
    validate do
      if !scopes.is_a?(Array) || (scopes - SCOPES).any?
        errors.add(:scopes, "must contain only read, write or publish")
      elsif scopes.empty?
        errors.add(:scopes, "must not be empty")
      elsif scopes.uniq.size != scopes.size
        errors.add(:scopes, "must not repeat a scope")
      end
    end

    def self.generate(name:, scopes: SCOPES, expires_at: nil, creator_identity: nil)
      secret = "ob_#{SecureRandom.base58(40)}"
      attributes = { name: name, scopes: scopes, expires_at: expires_at,
        token_digest: Digest::SHA256.hexdigest(secret), token_prefix: secret[0, 8] }
      attributes[:creator_identity] = creator_identity if creator_identity
      record = create!(attributes)
      [ record, secret ]
    end

    def status
      if revoked_at then :revoked
      elsif expires_at && expires_at <= Time.current then :expired
      else :active
      end
    end

    def self.authenticate(secret)
      return unless secret.is_a?(String) && secret.match?(/\Aob_[1-9A-HJ-NP-Za-km-z]{40}\z/)
      digest = Digest::SHA256.hexdigest(secret)
      record = active.find_by(token_digest: digest)
      return unless record && ActiveSupport::SecurityUtils.secure_compare(record.token_digest, digest)
      now = Time.current
      return unless active.where(id: record.id).update_all(last_used_at: now) == 1
      record.last_used_at = now
      record
    end
  end
end
