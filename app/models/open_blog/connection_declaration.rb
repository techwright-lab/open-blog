module OpenBlog
  class ConnectionDeclaration < ApplicationRecord
    include Immutable
    belongs_to :post
    validates :declared_by, :declared_on, presence: true
    validates :third_party_paid, inclusion: { in: [ true, false ] }
    validate :connections_are_named_relations

    private
      def connections_are_named_relations
        unless connections.is_a?(Array) && connections.all? { |entry| entry.is_a?(Hash) && entry["party"].present? && entry["relation"].present? }
          errors.add(:connections, "must be a list of named parties and relations")
        end
      end
  end
end
