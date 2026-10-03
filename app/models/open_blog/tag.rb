module OpenBlog
  class Tag < ApplicationRecord
    has_many :taggings, dependent: :destroy
    has_many :posts, through: :taggings

    before_validation { self.slug = name.to_s.parameterize if slug.blank? }
    validates :name, :slug, presence: true
    validates :name, uniqueness: { case_sensitive: false }
    validates :slug, uniqueness: true, format: { with: /\A[a-z0-9]+(?:[-_][a-z0-9]+)*\z/ }
  end
end
