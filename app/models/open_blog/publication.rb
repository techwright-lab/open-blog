module OpenBlog
  class Publication < ApplicationRecord
    include Immutable
    belongs_to :post
    belongs_to :revision

    validates :entry_type, inclusion: { in: %w[first substantive correction maintenance adopted] }
    validates :occurred_at, presence: true
    validates :note, presence: true, if: -> { entry_type == "correction" }
    validate :revision_belongs_to_post

    private
      def revision_belongs_to_post
        errors.add(:revision, "must belong to the post") if revision && revision.post != post
      end
  end
end
