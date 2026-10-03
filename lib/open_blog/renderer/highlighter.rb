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
        pre["tabindex"] = "0"
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
        pre["data-open-blog--code-copy-copied-label-value"] = translate(:copied)
        pre["data-open-blog--code-copy-error-label-value"] = translate(:copy_failed)
        button = Nokogiri::XML::Node.new("button", pre.document)
        button["type"] = "button"
        button["class"] = "ob-code-copy"
        button["data-action"] = "open-blog--code-copy#copy"
        button["data-open-blog--code-copy-target"] = "button"
        button["hidden"] = "hidden"
        button["aria-live"] = "polite"
        button["aria-label"] = translate(:copy_label)
        button.content = translate(:copy)
        pre.add_child(button)
      end

      def self.translate(key)
        I18n.t("open_blog.code.#{key}", locale: OpenBlog.config.locale)
      end
    end
  end
end
