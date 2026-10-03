module OpenBlog
  class Faq < ApplicationRecord
    belongs_to :post, inverse_of: :faqs
    validates :question, :answer, presence: true
    validates :position, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :post_id }
  end
end
