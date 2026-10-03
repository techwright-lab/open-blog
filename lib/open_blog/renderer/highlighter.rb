require "rouge"

module OpenBlog
  class Renderer
    module Highlighter
      def self.call(pre)
        code = pre.at_css("code")
        return unless code
        language = pre["lang"].presence || code["lang"].presence
        pre.remove_attribute("lang")
        lexer = Rouge::Lexer.find(language) if language
        code.inner_html = Rouge::Formatters::HTML.new.format(lexer.new.lex(code.text)) if lexer
        pre["class"] = "ob-highlight"
        if language
          pre["data-lang"] = language
          label = Nokogiri::XML::Node.new("span", pre.document)
          label["class"] = "ob-code-language"
          label["aria-hidden"] = "true"
          label.content = language
          pre.prepend_child(label)
        end
        pre["data-controller"] = "open-blog--code-copy"
        code["data-open-blog--code-copy-target"] = "code"
        button = Nokogiri::XML::Node.new("button", pre.document)
        button["type"] = "button"
        button["class"] = "ob-code-copy"
        button["data-action"] = "open-blog--code-copy#copy"
        button["data-open-blog--code-copy-target"] = "button"
        button["aria-label"] = "Copy code"
        button.content = "Copy"
        pre.add_child(button)
      end
    end
  end
end
