require "commonmarker"

module OpenBlog
  class Renderer
    module Markdown
      def self.render(text)
        Commonmarker.to_html(text.to_s.encode(Encoding::UTF_8), options: {
          extension: { header_ids: nil, footnotes: true, alerts: true, table: true, tasklist: true, strikethrough: true, autolink: true },
          render: { unsafe: false, hardbreaks: OpenBlog.config.markdown_hardbreaks }
        }, plugins: { syntax_highlighter: nil })
      end
    end
  end
end
