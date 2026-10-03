module OpenBlog
  class Series < ApplicationRecord
    self.table_name = "open_blog_series"
    has_many :posts, dependent: :nullify

    before_validation { self.slug = name.to_s.parameterize if slug.blank? }
    validates :name, :slug, presence: true
    validates :slug, uniqueness: true, format: { with: /\A[a-z0-9]+(?:[-_][a-z0-9]+)*\z/ }
  end
end
