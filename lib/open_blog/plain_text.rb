require "commonmarker"
require "nokogiri"

module OpenBlog
  module PlainText
    class << self
      def from_markdown(text)
        text_from_node(Commonmarker.parse(text.to_s.encode(Encoding::UTF_8))).strip
      end

      def from_html(html)
        Nokogiri::HTML.fragment(html.to_s).text
      end

      private

      def text_from_node(node)
        case node.type
        when :text, :code
          node.literal
        when :code_block
          "#{node.literal.sub(/\n+\z/, "")}\n"
        when :html_inline
          from_html(node.literal)
        when :html_block
          "#{from_html(node.literal)}\n"
        when :softbreak, :linebreak, :thematic_break
          "\n"
        else
          text = node.each.map { |child| text_from_node(child) }.join
          %i[paragraph heading table_row].include?(node.type) ? "#{text}\n" : text
        end
      end
    end
  end
end
