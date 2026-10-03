module OpenBlog
  module RichTextGuard
    extend ActiveSupport::Concern
    include ContentGuard

    private

    def content_guard_target?(attributes)
      candidate = attributes.stringify_keys
      candidate.fetch("record_type", record_type) == "OpenBlog::Post" && candidate.fetch("name", name) == "rich_body"
    end

    def content_guard_applies?
      (record_type == "OpenBlog::Post" && name == "rich_body") ||
        (attribute_in_database("record_type") == "OpenBlog::Post" && attribute_in_database("name") == "rich_body")
    end

    def content_guard_identity_changed?
      persisted? && %w[record_type record_id name].any? { |attribute| will_save_change_to_attribute?(attribute) }
    end

    def content_guard_parent
      record
    end
  end
end
