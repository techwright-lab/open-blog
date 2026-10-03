module OpenBlog
  class Approval < ApplicationRecord
    include Immutable
    belongs_to :post
    belongs_to :revision

    validates :kind, inclusion: { in: %w[sent imported declared] }
    validates :reviewer_name, :approved_at, presence: true
    validates :facts_checked, inclusion: { in: [ true, false ] }
    validates :declared_on, :declared_by, presence: true, if: -> { kind == "declared" }
    validates :confirmed_by, :evidence, presence: true, if: -> { kind == "imported" }
    validate :revision_belongs_to_post

    private
      def revision_belongs_to_post
        errors.add(:revision, "must belong to the post") if revision && revision.post != post
      end
  end
end
