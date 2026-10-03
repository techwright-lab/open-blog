module OpenBlog
  module ImmutableImageAttachment
    extend ActiveSupport::Concern

    STRUCTURAL_ATTRIBUTES = %w[name blob_id record_type record_id].freeze

    included do
      before_create :check_image_attachment_creation
      before_update :check_image_attachment_changes
      before_destroy :check_image_attachment_destruction, prepend: true
    end

    def update_columns(attributes)
      if image_attachment?(attributes.stringify_keys["record_type"]) && (attributes.keys.map(&:to_s) & STRUCTURAL_ATTRIBUTES).any?
        raise ActiveRecord::ReadOnlyRecord, "Stored image attachments cannot change"
      end
      super
    end

    private
      def image_attachment?(target_type = nil)
        [ record_type, record_type_in_database, target_type ].include?("OpenBlog::Image")
      end

      def check_image_attachment_creation
        return unless image_attachment?
        change = record&.attachment_changes&.fetch("file", nil)
        unless record&.saved_change_to_id? && change&.attachment.equal?(self)
          raise ActiveRecord::ReadOnlyRecord, "Image attachments must be created with their image"
        end
      end

      def check_image_attachment_changes
        if image_attachment? && (changes_to_save.keys & STRUCTURAL_ATTRIBUTES).any?
          raise ActiveRecord::ReadOnlyRecord, "Stored image attachments cannot change"
        end
      end

      def check_image_attachment_destruction
        raise ActiveRecord::ReadOnlyRecord, "Stored image attachments cannot be destroyed" if image_attachment?
      end
  end
end
