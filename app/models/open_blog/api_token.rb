require "digest"
require "active_support/core_ext/securerandom"

module OpenBlog
  class ApiToken < ApplicationRecord
    SCOPES = %w[read write publish].freeze
    scope :active, -> { where(revoked_at: nil).where("expires_at IS NULL OR expires_at > ?", Time.current) }

    validates :name, presence: true
    validates :token_digest, presence: true, uniqueness: true, format: { with: /\A[0-9a-f]{64}\z/ }
    validates :token_prefix, length: { is: 8 }
    validate do
      errors.add(:scopes, "must contain only read, write or publish") unless scopes.is_a?(Array) && (scopes - SCOPES).empty?
    end

    def self.generate(name:, scopes: SCOPES, expires_at: nil)
      secret = "ob_#{SecureRandom.base58(40)}"
      record = create!(name: name, scopes: scopes, expires_at: expires_at,
        token_digest: Digest::SHA256.hexdigest(secret), token_prefix: secret[0, 8])
      [ record, secret ]
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
