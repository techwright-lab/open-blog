module OpenBlog
  # Copied host migrations call these methods, so their names and arguments must stay stable.
  module RecordKeys
    UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
    ATTACHING_TABLES = %w[open_blog_images open_blog_authors].freeze

    module_function

    def attachment_type(connection)
      if connection.data_source_exists?("active_storage_attachments")
        column = connection.columns("active_storage_attachments").find { |candidate| candidate.name == "record_id" }
        column&.type == :uuid ? :uuid : :bigint
      else
        generators = Rails.configuration.generators
        generators.options.dig(generators.orm, :primary_key_type)&.to_sym == :uuid ? :uuid : :bigint
      end
    end

    def table_options(connection)
      attachment_type(connection) == :uuid ? { id: :uuid } : {}
    end

    def uuid?(model)
      model.type_for_attribute(model.primary_key).type == :uuid
    end

    def id?(model, value)
      uuid?(model) ? value.is_a?(String) && value.match?(UUID) : value.is_a?(Integer) && value.positive?
    end

    def uuid_id?(model, value)
      uuid?(model) && value.is_a?(String) && value.match?(UUID)
    end
  end
end
