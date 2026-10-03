require "set"

module OpenBlog
  class Renderer
    class Transform
      def initialize(document, post: nil)
        @fragment = Sanitizer.restore!(document)
        @post = post
      end

      def call
        headings = @fragment.css("h1,h2,h3,h4,h5,h6")
        shift = headings.any? ? 2 - headings.map { |node| node.name[1].to_i }.min : 0
        used_ids = @fragment.css("[id]").map { |node| node["id"] }.to_set
        @fragment.css("h1,h2,h3,h4,h5,h6,pre,img,table,a").each do |node|
          case node.name
          when /\Ah[1-6]\z/ then heading(node, shift, used_ids)
          when "pre" then Highlighter.call(node)
          when "img" then image(node)
          when "table" then table(node)
          when "a" then link(node)
          end
        end
        @fragment
      end

      private

      def heading(node, shift, used_ids)
        node.name = "h#{[ node.name[1].to_i + shift, 6 ].min}"
        base = node.text.parameterize.presence || "section"
        identifier, suffix = base, 0
        while used_ids.include?(identifier)
          suffix += 1
          identifier = "#{base}-#{suffix}"
        end
        used_ids << identifier
        node["id"] = identifier
        anchor = Nokogiri::XML::Node.new("a", node.document)
        anchor["class"] = "ob-heading-anchor"
        anchor["href"] = "##{identifier}"
        anchor["aria-label"] = I18n.t("open_blog.headings.link", heading: node.text, locale: OpenBlog.config.locale)
        anchor.content = "#"
        node.add_child(anchor)
      end

      def image(node)
        stored = ImageResolution.image_for_url(node["src"], post: @post)
        if stored
          node["src"] = stored.path
          node["width"] = stored.width.to_s if stored.width
          node["height"] = stored.height.to_s if stored.height
        end
        node["alt"] ||= ""
        node["loading"] = "lazy"
        figure = node.ancestors("figure").first
        unless figure
          figure = Nokogiri::XML::Node.new("figure", node.document)
          node.replace(figure)
          figure.add_child(node)
          lift_figure(figure)
        end
        figure["class"] = "ob-figure"
        if node["title"].present? && !figure.at_css("figcaption")
          caption = Nokogiri::XML::Node.new("figcaption", node.document)
          caption.content = node["title"]
          figure.add_child(caption)
        end
      end

      def lift_figure(figure)
        while figure.parent && %w[p a strong em del span sup sub].include?(figure.parent.name)
          parent = figure.parent
          before, after = copy_wrapper(parent), copy_wrapper(parent)
          figure.xpath("preceding-sibling::node()").each { |sibling| before.add_child(sibling) }
          figure.xpath("following-sibling::node()").each { |sibling| after.add_child(sibling) }
          unless parent.name == "p"
            wrapper = copy_wrapper(parent)
            figure.children.each { |child| wrapper.add_child(child) }
            figure.add_child(wrapper)
          end
          parent.add_previous_sibling(before) if before.children.any?
          parent.add_previous_sibling(figure)
          parent.add_previous_sibling(after) if after.children.any?
          parent.remove
        end
      end

      def copy_wrapper(node)
        node.dup(0).tap do |copy|
          node.attribute_nodes.each { |attribute| copy[attribute.name] = attribute.value }
        end
      end

      def table(node)
        wrapper = Nokogiri::XML::Node.new("div", node.document)
        wrapper["class"] = "ob-table"
        wrapper["tabindex"] = "0"
        node.replace(wrapper)
        wrapper.add_child(node)
      end

      def link(node)
        return if node["href"].blank?
        uri = URI.parse(node["href"])
        return unless uri.host
        base = URI.parse(OpenBlog.config.public_base_url) if OpenBlog.config.public_base_url
        return if base && uri.host.casecmp?(base.host) && uri.port == base.port
        node["rel"] = (node["rel"].to_s.split + [ "noopener" ]).uniq.join(" ")
      rescue URI::InvalidURIError
        nil
      end
    end
  end
end
