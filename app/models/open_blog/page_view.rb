module OpenBlog
  class PageView < ApplicationRecord
    belongs_to :post
    validates :day, presence: true
    validates :views, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  end
end
