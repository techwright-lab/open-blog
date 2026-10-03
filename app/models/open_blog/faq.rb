module OpenBlog
  class Faq < ApplicationRecord
    include ContentGuard
    belongs_to :post, inverse_of: :faqs
    validates :question, :answer, presence: true
    validates :position, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :post_id }

    private

    def content_guard_applies?
      true
    end

    def content_guard_identity_changed?
      persisted? && will_save_change_to_post_id?
    end

    def content_guard_parent
      post
    end
  end
end
