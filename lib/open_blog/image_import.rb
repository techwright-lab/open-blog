require "delegate"
require "digest"
require "stringio"
require "tempfile"
require "marcel"

module OpenBlog
  class ImageImport
    def self.prepare(input)
      unless input.is_a?(Hash) && input.keys.map(&:to_s) == [ "signed_id" ]
        raise Error::ImageNotPermitted
      end
      signed_id = input[:signed_id] || input["signed_id"]
      raise Error::ImageNotPermitted unless signed_id.is_a?(String) && signed_id.present?
      blob = ActiveStorage::Blob.find_signed!(signed_id)
      new(blob).prepare
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound, ActiveStorage::FileNotFoundError
      raise Error::ImageNotPermitted
    end

    def initialize(blob)
      @blob = blob
    end

    def prepare
      permitted!(@blob.content_type)
      limit = OpenBlog.config.max_image_bytes
      raise Error::ImageNotPermitted if @blob.byte_size > limit
      bytes = +"".b
      @blob.download do |chunk|
        raise Error::ImageNotPermitted if bytes.bytesize + chunk.bytesize > limit
        bytes << chunk
      end
      unless bytes.bytesize == @blob.byte_size && Digest::MD5.base64digest(bytes) == @blob.checksum
        raise Error::ImageNotPermitted
      end
      content_type = Marcel::MimeType.for(StringIO.new(bytes))
      permitted!(content_type)
      raise Error::ImageNotPermitted unless content_type == @blob.content_type
      source = ReadOnlySource.new(@blob, bytes)
      analyzer = ActiveStorage.analyzers.find { |candidate| candidate.accept?(source) }
      raise Error::ImageNotPermitted unless analyzer
      metadata = analyzer.new(source).metadata
      dimensions = metadata.symbolize_keys.slice(:width, :height)
      unless dimensions.size == 2 && dimensions.values.all? { |value| value.is_a?(Integer) && value.positive? }
        raise Error::ImageNotPermitted
      end
      Prepared.new(@blob, { sha256: Digest::SHA256.hexdigest(bytes), filename: @blob.filename.to_s,
        byte_size: bytes.bytesize, content_type: content_type, **dimensions })
    end

    private

    def permitted!(content_type)
      unless content_type != "image/svg+xml" && OpenBlog.config.image_content_types.include?(content_type)
        raise Error::ImageNotPermitted
      end
    end

    class ReadOnlySource < SimpleDelegator
      def initialize(blob, bytes)
        super(blob)
        @bytes = bytes
      end

      def open(tmpdir: nil, **)
        Tempfile.create([ "open-blog-image", File.extname(filename.to_s) ], tmpdir, binmode: true) do |file|
          file.write(@bytes)
          file.rewind
          yield file
        end
      end
    end

    class Prepared
      attr_reader :attributes

      def initialize(blob, attributes)
        @blob, @attributes = blob, attributes.freeze
      end

      def image
        @image ||= Image.find_by(sha256: attributes[:sha256]) || Image.new(attributes)
      end

      def persist(uploaded_by: nil)
        Image.transaction(requires_new: true) do
          existing = Image.find_by(sha256: attributes[:sha256])
          next existing if existing
          blob = ActiveStorage::Blob.lock.find(@blob.id)
          existing = Image.find_by(sha256: attributes[:sha256])
          next existing if existing
          fields = %w[key service_name checksum byte_size content_type]
          unless blob.attributes.slice(*fields) == @blob.attributes.slice(*fields)
            raise Error::ImageNotPermitted
          end
          blob.update!(metadata: blob.metadata.merge("identified" => true, "analyzed" => true,
            "width" => attributes[:width], "height" => attributes[:height]))
          record = Image.new(attributes.merge(uploaded_by: uploaded_by))
          record.file = blob
          record.save!
          record
        end
      rescue ActiveRecord::RecordNotUnique
        Image.find_by!(sha256: attributes[:sha256])
      rescue ActiveRecord::RecordInvalid => error
        errors = error.record.errors.details
        if error.record.is_a?(Image) && errors.keys == [ :sha256 ] && errors[:sha256].all? { |detail| detail[:error] == :taken }
          existing = Image.find_by(sha256: attributes[:sha256])
          return existing if existing
        end
        raise Error::ImageNotPermitted
      rescue ActiveRecord::RecordNotFound
        raise Error::ImageNotPermitted
      end
    end
  end
end
