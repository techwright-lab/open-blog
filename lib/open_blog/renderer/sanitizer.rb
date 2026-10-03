require "uri"
require "rails/html/sanitizer"
require "nokogiri"

module OpenBlog
  class Renderer
    module Sanitizer
      TAGS = %w[p h1 h2 h3 h4 h5 h6 ul ol li a strong em del code pre blockquote br hr img figure figcaption table thead tbody tr th td sup sub section div span input].freeze
      ATTRIBUTES = %w[href rel src alt title width height lang align].freeze
      TOKEN = "data-ob-render-token".freeze
      Document = Struct.new(:fragment, :metadata, keyword_init: true)

      def self.call(html, trusted: false)
        fragment = Nokogiri::HTML5.fragment(html)
        fragment.css("pre").each do |node|
          code = Nokogiri::XML::Node.new("code", node.document)
          code["lang"] = node.at_css("code")["lang"] if node.at_css("code")&.key?("lang")
          code.content = node.text
          node.children.remove
          node.add_child(code)
        end
        fragment.css("code").each { |node| node.content = node.text }
        metadata = trusted ? capture(fragment) : {}
        output = Rails::HTML5::SafeListSanitizer.new.sanitize(fragment.to_html, scrubber: Scrubber.new(metadata))
        Document.new(fragment: Nokogiri::HTML5.fragment(output), metadata: metadata)
      end

      def self.safe_url?(value, image: false)
        return false unless value.is_a?(String) && value.present?
        uri = URI.parse(value)
        uri.scheme.nil? || (image ? %w[http https] : %w[http https mailto]).include?(uri.scheme.downcase)
      rescue URI::InvalidURIError
        false
      end

      def self.restore!(document)
        document.fragment.css("[#{TOKEN}]").each do |node|
          document.metadata.fetch(node[TOKEN], {}).each { |name, value| node[name] = value }
          node.remove_attribute(TOKEN)
        end
        document.fragment
      end

      def self.capture(fragment)
        metadata = {}
        fragment.traverse do |node|
          next unless node.element?
          attributes = {}
          classes = node["class"].to_s.split.select do |name|
            name.match?(/\A(?:markdown-alert(?:-(?:note|tip|important|warning|caution|title))?|footnotes?|footnote-(?:ref|backref)|task-list(?:-item)?)\z/)
          end
          attributes["class"] = classes.join(" ") if classes.any?
          if node["id"].to_s.match?(/\Afn(?:ref)?-/)
            attributes["id"] = "ob-footnote-#{node['id']}"
          end
          if node["href"].to_s.match?(/\A#fn(?:ref)?-/)
            attributes["href"] = "#ob-footnote-#{node['href'].delete_prefix('#')}"
          end
          %w[data-footnote-ref data-footnotes data-footnote-backref data-footnote-backref-idx aria-label].each do |name|
            attributes[name] = node[name] if node.key?(name)
          end
          next if attributes.empty?
          token = metadata.length.to_s
          metadata[token] = attributes
          node[TOKEN] = token
        end
        metadata
      end
      private_class_method :capture
    end
  end
end
