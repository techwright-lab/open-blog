require "delegate"
require "digest"
require "stringio"
require "tempfile"
require "marcel"

module OpenBlog
  class ImageImport
    def self.prepare(input)
      return prepare_url(input[:url] || input["url"]) if input.is_a?(Hash) && input.keys.map(&:to_s) == [ "url" ]
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

    def self.prepare_url(url)
      fetched = ImageFetch.call(url, max_bytes: OpenBlog.config.max_image_bytes, policy: OpenBlog.config.image_fetch_policy)
      prepared = prepare_upload(fetched.fetch(:io), filename: fetched.fetch(:filename), content_type: fetched.fetch(:content_type))
      Prepared.new(nil, prepared.attributes.merge(source_url: url), bytes: prepared.bytes)
    ensure
      fetched&.fetch(:io)&.close
    end

    def self.prepare_upload(io, filename:, content_type:)
      unless io.respond_to?(:read) && filename.is_a?(String) && filename.present? && !filename.include?("\0")
        raise Error::ImageNotPermitted
      end
      filename = ActiveStorage::Filename.new(filename.tr("\\", "/").split("/").last.to_s).sanitized
      raise Error::ImageNotPermitted if filename.blank?
      bytes = +"".b
      io.rewind if io.respond_to?(:rewind)
      limit = OpenBlog.config.max_image_bytes
      loop do
        chunk = io.read([ 64 * 1024, limit - bytes.bytesize + 1 ].min)
        break if chunk.nil? || chunk.empty?
        bytes << chunk
        raise Error::ImageNotPermitted if bytes.bytesize > limit
      end
      source = ActiveStorage::Blob.new(filename: filename, content_type: content_type, byte_size: bytes.bytesize)
      new(source).prepare_bytes(bytes.freeze, uploaded: true)
    rescue IOError, SystemCallError
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
      prepare_bytes(bytes)
    end

    def prepare_bytes(bytes, uploaded: false)
      permitted!(@blob.content_type)
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
      Prepared.new(uploaded ? nil : @blob, { sha256: Digest::SHA256.hexdigest(bytes), filename: @blob.filename.to_s,
        byte_size: bytes.bytesize, content_type: content_type, **dimensions }, bytes: uploaded ? bytes : nil)
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
      attr_reader :attributes, :bytes

      def initialize(blob, attributes, bytes: nil)
        @blob, @attributes, @bytes = blob, attributes.freeze, bytes
      end

      def image
        @image ||= Image.find_by(sha256: attributes[:sha256]) || Image.new(attributes)
      end

      def persist(uploaded_by: nil)
        Image.transaction(requires_new: true) do
          existing = Image.find_by(sha256: attributes[:sha256])
          next existing if existing
          next persist_upload(uploaded_by) unless @blob
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
      private

      def persist_upload(uploaded_by)
        record = Image.new(attributes.merge(uploaded_by: uploaded_by))
        record.file = { io: StringIO.new(bytes), filename: attributes[:filename], content_type: attributes[:content_type],
          identify: false, metadata: { "identified" => true, "analyzed" => true,
            "width" => attributes[:width], "height" => attributes[:height] } }
        record.save!
        record
      end
    end
  end
end
