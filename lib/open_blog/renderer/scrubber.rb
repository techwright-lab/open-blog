module OpenBlog
  class Renderer
    class Scrubber < Rails::HTML::PermitScrubber
      def initialize(metadata)
        super()
        self.tags = Sanitizer::TAGS
        self.attributes = Sanitizer::ATTRIBUTES + %w[type checked disabled] + [ Sanitizer::TOKEN ]
        @metadata = metadata
      end

      def scrub(node)
        if node.element? && ((node.name == "input" && (node["type"] != "checkbox" || !node.key?("disabled"))) ||
            (node.name == "img" && !Sanitizer.safe_url?(node["src"], image: true)))
          node.remove
          return STOP
        end
        super
      end

      protected

      def scrub_attribute(node, attribute)
        name = attribute.name
        invalid_input = %w[type checked disabled].include?(name) && node.name != "input"
        invalid_token = name == Sanitizer::TOKEN && !@metadata.key?(attribute.value)
        invalid_url = %w[href src].include?(name) && !Sanitizer.safe_url?(attribute.value, image: name == "src")
        if invalid_input || invalid_token || invalid_url
          attribute.remove
        else
          super
        end
      end
    end
  end
end
