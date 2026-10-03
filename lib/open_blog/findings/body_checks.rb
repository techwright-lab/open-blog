require "uri"

module OpenBlog
  module Findings
    module BodyChecks
      class << self
        def build
          [
            Check.new(code: :heading_level_skipped, rule: "T9", message: "Use consecutive heading levels within the body.",
              location: ->(_, _, index) { "body.headings[#{index}]" }) { |post, context| skipped_heading(post, context) },
            Check.new(code: :heading_h1_in_body, rule: "T10", message: "Use a level-two heading or lower in the body; the title supplies level one.",
              location: ->(_, _, index) { "body.headings[#{index}]" }) { |post, context| headings(post, context).index { |node| node.name == "h1" } },
            Check.new(code: :image_alt_absent, rule: "T13", message: "Describe this image in alternative text.",
              location: ->(_, _, location) { location }) { |post, context| absent_alt(post, context) },
            Check.new(code: :image_external, rule: "E19", message: "Store this image in the blog to keep a stable copy of its bytes.",
              location: ->(_, _, index) { "body.images[#{index}]" }) { |post, context| images(post, context).index { |node| external?(node["src"]) } }
          ]
        end

        private

        def document(post, context)
          context[:body_document] ||= Renderer.document(post)
        end

        def headings(post, context)
          document(post, context).css("h1, h2, h3, h4, h5, h6")
        end

        def images(post, context)
          document(post, context).css("img")
        end

        def skipped_heading(post, context)
          levels = headings(post, context).map { |node| node.name.delete_prefix("h").to_i }
          pair = levels.each_cons(2).find_index { |previous, current| current > previous + 1 }
          pair + 1 if pair
        end

        def absent_alt(post, context)
          return "cover_alt" if post.cover_image && post.cover_alt.blank?
          index = images(post, context).index { |node| node["alt"].blank? }
          "body.images[#{index}].alt" if index
        end

        def external?(source)
          return false if source.blank?
          uri = URI.parse(source)
          return false unless uri.host
          base = URI.parse(OpenBlog.config.public_base_url.to_s)
          uri.host.downcase != base.host&.downcase
        rescue URI::InvalidURIError
          false
        end
      end
    end
  end
end
