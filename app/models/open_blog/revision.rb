module OpenBlog
  class Revision < ApplicationRecord
    include Immutable
    belongs_to :post
    has_many :approvals, dependent: :restrict_with_exception
    has_many :publications, dependent: :restrict_with_exception

    validates :identifier, presence: true, uniqueness: { scope: :post_id }, format: { with: /\A[0-9a-f]{64}\z/ }
    validates :payload, presence: true
    validates :made_by_ai, inclusion: { in: [ true, false ] }, allow_nil: true
  end
end
