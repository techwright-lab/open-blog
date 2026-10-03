require "base64"
require "tempfile"

module OpenBlog
  module Mcp
    module ImageInput
      def self.with_upload(arguments)
        if arguments.key?(:url)
          raise Error::ImageNotPermitted unless arguments.keys == [ :url ]
          return yield(arguments)
        end
        encoded = arguments[:base64]
        maximum = OpenBlog.config.max_image_bytes
        raise Error::ImageNotPermitted unless encoded.is_a?(String) && encoded.bytesize <= ((maximum + 2) / 3) * 4
        bytes = Base64.strict_decode64(encoded)
        raise Error::ImageNotPermitted if bytes.bytesize > maximum
        filename, content_type = arguments.values_at(:filename, :content_type)
        raise Error::ImageNotPermitted unless filename.is_a?(String) && filename.present? && content_type.is_a?(String) && content_type.present?
        Tempfile.create([ "open-blog-upload", ".bin" ], binmode: true) do |file|
          file.write(bytes)
          file.rewind
          upload = ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: filename, type: content_type)
          yield(file: upload)
        end
      rescue ArgumentError
        raise Error::ImageNotPermitted
      end
    end
  end
end
