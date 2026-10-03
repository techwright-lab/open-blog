module OpenBlog
  class Image < ApplicationRecord
    include Immutable
    has_one_attached :file, service: ->(_) { OpenBlog.config.storage_service || Rails.application.config.active_storage.service }

    validates :sha256, presence: true, uniqueness: true, format: { with: /\A[0-9a-f]{64}\z/ }
    validates :filename, :content_type, presence: true
    validates :byte_size, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :width, :height, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

    module ImmutableFile
      %i[attach detach purge purge_later].each do |operation|
        define_method(operation) do |*arguments, **options|
          raise ActiveRecord::ReadOnlyRecord, "Stored image files cannot change" if record.persisted?
          super(*arguments, **options)
        end
      end
    end

    def self.from_upload(io, filename:, content_type:, uploaded_by: nil)
      ImageImport.prepare_upload(io, filename: filename, content_type: content_type).persist(uploaded_by: uploaded_by)
    end

    def self.from_signed_id(signed_id, uploaded_by: nil)
      ImageImport.prepare(signed_id: signed_id).persist(uploaded_by: uploaded_by)
    end

    def self.from_url(url, uploaded_by: nil)
      ImageImport.prepare(url: url).persist(uploaded_by: uploaded_by)
    end

    def path
      "#{OpenBlog.mount_path.chomp("/")}/media/#{sha256}/#{ERB::Util.url_encode(filename)}"
    end

    def file
      super.extend(ImmutableFile)
    end

    def file=(attachable)
      raise ActiveRecord::ReadOnlyRecord, "Stored image files cannot change" if persisted?
      super
    end
  end
end
