module OpenBlog
  class Category < ApplicationRecord
    has_many :posts, dependent: :nullify

    before_validation { self.slug = name.to_s.parameterize if slug.blank? }
    validates :name, :slug, presence: true, uniqueness: true
    validates :slug, format: { with: /\A[a-z0-9]+(?:[-_][a-z0-9]+)*\z/ }
    validates :position, numericality: { only_integer: true }
  end
end
