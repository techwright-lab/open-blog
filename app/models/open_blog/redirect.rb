module OpenBlog
  class Redirect < ApplicationRecord
    belongs_to :post, optional: true
    validates :old_path, :occurred_on, presence: true
    validates :old_path, uniqueness: true, format: { with: /\A\/(?!\/)/ }
    validates :source, inclusion: { in: %w[slug_change removal unpublish adoption manual] }
    validate :preserve_history, on: :update

    private
      def preserve_history
        if (changed - %w[new_path updated_at]).any?
          errors.add(:base, "Only the redirect target can change")
        end
      end
  end
end
