require "uri"

module OpenBlog
  module FaqHelper
    def open_blog_faq(post)
      entries = post.faq_list
      return "".html_safe if entries.empty?
      heading = tag.h2(open_blog_translate("faq.heading"), id: open_blog_faq_section_id(post))
      items = entries.map do |entry|
        question = tag.h3(ERB::Util.html_escape(String.new(entry[:question].to_s)))
        paragraphs = entry[:answer].to_s.gsub(/\r\n?/, "\n").split(/\n[\t ]*\n+/).map do |paragraph|
          tag.p(safe_join(paragraph.split("\n", -1).map { |line| open_blog_faq_links(line) }, safe_join([ tag.br, "\n" ])))
        end
        tag.div(safe_join([ question, *paragraphs ], "\n"), class: "ob-faq-entry", data: { open_blog_faq_entry: true })
      end
      tag.section(safe_join([ heading, *items ], "\n"), class: "ob-faq", data: { open_blog_faq: true })
    end

    def open_blog_faq_section_id(post, body: nil)
      body ||= Nokogiri::HTML5.fragment(Renderer.render(post))
      used = body.css("[id]").map { |node| node["id"] }
      identifier, suffix = "open-blog-faq", 0
      while used.include?(identifier)
        suffix += 1
        identifier = "open-blog-faq-#{suffix}"
      end
      identifier
    end

    private

    def open_blog_faq_links(line)
      line = String.new(line)
      parts, offset = [], 0
      line.to_enum(:scan, %r{https?://[^\s<>"']+}i).each do
        match = Regexp.last_match
        parts << line[offset...match.begin(0)]
        candidate = match[0]
        url = candidate.sub(/[.,;:!?]+\z/, "")
        { ")" => "(", "]" => "[", "}" => "{" }.each do |closing, opening|
          url = url.chop while url.end_with?(closing) && url.count(closing) > url.count(opening)
        end
        url = url.sub(/[.,;:!?]+\z/, "")
        parts << (open_blog_faq_http_url?(url) ? link_to(url, url, rel: "noopener") : url)
        parts << candidate[url.length..]
        offset = match.end(0)
      end
      parts << line[offset..]
      safe_join(parts)
    end

    def open_blog_faq_http_url?(url)
      parsed = URI.parse(url)
      %w[http https].include?(parsed.scheme&.downcase) && parsed.host.present?
    rescue URI::InvalidURIError
      false
    end
  end
end
