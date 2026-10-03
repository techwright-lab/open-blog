module OpenBlog
  class Baseline < ApplicationRecord
    include Immutable
    belongs_to :post
    belongs_to :adopted_revision, class_name: "OpenBlog::Revision"

    validates :post_id, uniqueness: true
    validates :adopted_at, presence: true
    validates :provenance, inclusion: { in: %w[ai_assisted human_written unknown] }
    validates :source_id, uniqueness: { scope: :source_system }, allow_nil: true
    validates :source_body_sha256, format: { with: /\A[0-9a-f]{64}\z/ }, allow_nil: true
    validate :separate_declared_and_evidenced_dates
    validate :revision_belongs_to_post

    private
      def separate_declared_and_evidenced_dates
        if first_published_at && declared_first_published_at
          errors.add(:declared_first_published_at, "cannot accompany an evidenced first publication date")
        end
      end

      def revision_belongs_to_post
        errors.add(:adopted_revision, "must belong to the post") if adopted_revision && adopted_revision.post != post
      end
  end
end
