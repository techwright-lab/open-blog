require "digest"
require "uri"

module OpenBlog
  class ImageResolution
    PAYLOAD_FIELDS = %w[url sha256 alt role].freeze

    def self.prepare(attributes:, post: nil)
      attributes = attributes.symbolize_keys
      format = attributes.fetch(:body_format, post&.body_format || OpenBlog.config.default_body_format).to_s
      unless OpenBlog.config.body_formats.map(&:to_s).include?(format)
        raise Error::BodyFormatNotPermitted
      end
      body = attributes.key?(:body) ? attributes[:body] : (format == "rich_text" ? post&.rich_body&.body : post&.body_markdown)
      raise Error::ValidationFailed.new(details: [ "body" ]) unless body.nil? || body.is_a?(String) || body.is_a?(ActionText::Content)
      text = format == "rich_text" ? ActionText::Content.new(body.to_s).to_html : body.to_s
      digest = source_digest(text, format)
      if post && !attributes.key?(:body) && !attributes.key?(:body_format) && post.body_image_source_digest == digest
        return Prepared.new(digest, post.body_image_manifest.deep_dup, {}, sources(text, format), reuse_current: true)
      end
      build(text, format, external: true)
    end

    def self.prepare_inputs(attributes)
      %i[cover_image social_image].each_with_object({}) do |field, prepared|
        value = attributes[field] || attributes[field.to_s]
        if value.is_a?(Hash) && (value.keys.map(&:to_s) & %w[signed_id url]).any?
          prepared[field] = ImageImport.prepare(value)
        end
      end
    end

    def self.source_digest(text, format)
      Digest::SHA256.hexdigest("#{format}\0#{text}")
    end

    def self.fingerprint(post)
      source_digest(post.body_for_payload, post.body_format)
    end

    def self.fetch_external(url)
      fetched = ImageFetch.call(url)
      Digest::SHA256.hexdigest(fetched.fetch(:io).read)
    rescue Error::ImageNotPermitted
      nil
    ensure
      fetched&.fetch(:io)&.close
    end

    def self.native!(post)
      return if post.body_image_source_digest == fingerprint(post)
      build(post.body_for_payload, post.body_format, external: false).materialize(post)
    end

    def self.body_images(post)
      entries = if post.body_image_source_digest == fingerprint(post)
        post.body_image_manifest
      else
        build(post.body_for_payload, post.body_format, external: false, import: false).entries
      end
      entries.map { |entry| entry.slice(*PAYLOAD_FIELDS) }
    end

    def self.image_for_attachment(blob, post: nil)
      return unless blob.is_a?(ActiveStorage::Blob)
      image = Image.joins(:file_attachment).find_by(active_storage_attachments: { blob_id: blob.id })
      return image if image
      entry = post&.body_image_manifest&.find { |candidate| candidate["blob_id"] == blob.id }
      Image.new(entry.fetch("image_attributes")) if entry && entry["image_attributes"]
    end

    def self.image_for_url(url, post: nil)
      prefix = "#{OpenBlog.mount_path.chomp('/')}/media/"
      match = url.to_s.match(/\A#{Regexp.escape(prefix)}([0-9a-f]{64})\//)
      return unless match
      Image.find_by(sha256: match[1]) || begin
        entry = post&.body_image_manifest&.find { |candidate| candidate["sha256"] == match[1] }
        Image.new(entry.fetch("image_attributes")) if entry && entry["image_attributes"]
      end
    end

    def self.build(text, format, external:, import: true)
      imports = {}
      source_entries = sources(text, format)
      entries = source_entries.filter_map do |source|
        blob = source[:blob]
        image = blob ? image_for_attachment(blob) : image_for_url(source[:url])
        if blob && !image && import
          prepared = imports[blob.id] ||= ImageImport.prepare(signed_id: blob.signed_id)
          image = prepared.image
        end
        next if blob && !image
        url = image ? image.path : source[:url]
        sha = image&.sha256 || (external && URI.parse(url).host ? fetch_external(url) : nil) || ""
        entry = { "url" => url, "sha256" => sha, "alt" => source[:alt].to_s, "role" => "body" }
        if blob
          entry["blob_id"] = blob.id
          entry["image_attributes"] = image.attributes.slice("sha256", "filename", "content_type", "byte_size", "width", "height")
        end
        entry
      end
      Prepared.new(source_digest(text, format), entries, imports, source_entries)
    end
    private_class_method :build

    def self.sources(text, format)
      html = format == "markdown" ? Renderer::Markdown.render(text) : text
      fragment = Nokogiri::HTML5.fragment(html)
      attachments = {}
      prefix = "/open-blog-prepared-attachment/"
      urls = fragment.css("img[src]").map { |node| node["src"] }
      prefix += "x/" while urls.any? { |url| url.start_with?(prefix) }
      fragment.css("action-text-attachment").each_with_index do |node, index|
        attachable = ActionText::Attachable.from_node(node)
        next node.remove unless attachable.is_a?(ActiveStorage::Blob) && attachable.content_type.start_with?("image/")
        image = Nokogiri::XML::Node.new("img", fragment.document)
        image["src"] = "#{prefix}#{index}"
        image["alt"] = node["alt"].presence || PlainText.from_html(node["caption"].to_s)
        attachments[image["src"]] = attachable
        node.replace(image)
      end
      document = Renderer::Sanitizer.call(fragment.to_html)
      Renderer::Sanitizer.restore!(document).css("img[src]").map do |node|
        blob = attachments[node["src"]]
        { url: blob ? nil : node["src"], alt: node["alt"], blob: blob }
      end
    end
    private_class_method :sources

    class Prepared
      attr_reader :entries

      def initialize(digest, entries, imports, sources, reuse_current: false)
        @digest, @entries, @imports, @sources = digest, entries, imports, sources
        @reuse_current = reuse_current
      end

      def verify!(post)
        current = ImageResolution.fingerprint(post)
        return if current == @digest
        sources = ImageResolution.send(:sources, post.body_for_payload, post.body_format)
        unless sources == @sources
          raise Error::ValidationFailed.new(details: [ "body" ])
        end
        @digest = current
      end

      def preview(post)
        verify!(post)
        post.body_image_source_digest = @digest
        post.body_image_manifest = entries.deep_dup
      end

      def materialize(post, actor: nil)
        if @reuse_current && post.body_image_source_digest == ImageResolution.fingerprint(post)
          @digest = post.body_image_source_digest
          @entries = post.body_image_manifest.deep_dup
          @sources = ImageResolution.send(:sources, post.body_for_payload, post.body_format)
        end
        verify!(post)
        images = @imports.transform_values { |prepared| prepared.persist(uploaded_by: actor) }
        @entries = entries.map do |entry|
          image = images[entry["blob_id"]]
          image ? entry.merge("url" => image.path, "sha256" => image.sha256,
            "image_attributes" => image.attributes.slice("sha256", "filename", "content_type", "byte_size", "width", "height")) : entry
        end
        preview(post)
      end
    end
  end
end
