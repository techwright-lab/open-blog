require "digest"

module OpenBlog
  class Renderer
    VERSION = 2
    autoload :Markdown, "open_blog/renderer/markdown"
    autoload :RichText, "open_blog/renderer/rich_text"
    autoload :Sanitizer, "open_blog/renderer/sanitizer"
    autoload :Scrubber, "open_blog/renderer/scrubber"
    autoload :Transform, "open_blog/renderer/transform"
    autoload :Highlighter, "open_blog/renderer/highlighter"

    class << self
      def render(post, cache: true)
        return render_string(post.body_for_payload, format: post.body_format, post: post) unless post.persisted? && cache
        options = [ OpenBlog.config.markdown_hardbreaks, OpenBlog.config.public_base_url, OpenBlog.config.locale.to_s ]
        configuration = Digest::SHA256.hexdigest(JSON.generate(options))
        Rails.cache.fetch([ "open_blog/body", post.id, post.current_revision_identifier, VERSION, configuration ]) do
          render_string(post.body_for_payload, format: post.body_format, post: post)
        end.html_safe
      end

      def render_string(text, format:, post: nil)
        parsed = sanitized(text, format: format, post: post)
        Transform.new(parsed, post: post).call.to_html.html_safe
      end

      def document(post)
        parsed = sanitized(post.body_for_payload, format: post.body_format, post: post)
        Sanitizer.restore!(parsed)
      end

      def body_images(post)
        ImageResolution.body_images(post)
      end

      private

      def sanitized(text, format:, post:)
        case format.to_s
        when "markdown"
          Sanitizer.call(Markdown.render(text), trusted: true)
        when "rich_text"
          Sanitizer.call(RichText.render(text, post: post))
        else
          raise ArgumentError, "Unsupported body format: #{format}"
        end
      end
    end
  end
end
