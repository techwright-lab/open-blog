module OpenBlog
  class Author < ApplicationRecord
    has_many :posts, dependent: :restrict_with_exception
    has_one_attached :avatar

    before_validation { self.slug = name.to_s.parameterize if slug.blank? }
    validates :name, :slug, presence: true
    validates :slug, uniqueness: true, format: { with: /\A[a-z0-9]+(?:[-_][a-z0-9]+)*\z/ }
    validates :author_type, inclusion: { in: %w[person organization] }
  end
end
