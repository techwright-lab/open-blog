module OpenBlog
  class ApiTokenEvent < ApplicationRecord
    ACTIONS = %w[issued rotated revoked].freeze

    belongs_to :api_token
    validates :action, inclusion: { in: ACTIONS }
    validates :actor_identity, presence: true
  end
end
