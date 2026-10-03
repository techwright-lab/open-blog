module OpenBlog
  module Immutable
    extend ActiveSupport::Concern

    included do
      before_destroy(prepend: true) { raise ActiveRecord::ReadOnlyRecord, "Stored records cannot be destroyed" if persisted? }
    end

    def readonly?
      persisted? || super
    end
  end
end
