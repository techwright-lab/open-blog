module OpenBlog
  class SurfaceReport
    class ExpectedContent
      class RenderingController < OpenBlog::ApplicationController
        helper do
          def open_blog_notices(*) = "".html_safe
        end
      end

      def self.call(post, payload, base_url:)
        snapshot = post.dup
        %w[title description search_title search_description].each { |field| snapshot.public_send("#{field}=", payload.fetch(field)) }
        snapshot.author = post.author
        snapshot.author_name = payload.fetch("author")
        snapshot.define_singleton_method(:body_for_payload) { payload.fetch("body") }
        snapshot.define_singleton_method(:faq_list) { payload.fetch("faq").map(&:symbolize_keys) }
        cover = payload.fetch("images").find { |entry| entry["role"] == "cover" }
        snapshot.cover_image = cover && Image.find_by(sha256: cover["sha256"])
        snapshot.cover_alt = cover&.fetch("alt")
        page = ReaderPage.new(kind: :preview, record: snapshot, path: post.path, base_url: base_url)
        html = RenderingController.render(template: "open_blog/posts/show", layout: false,
          assigns: { open_blog_page: page, related_posts: [], related_cache_key: [] })
        Nokogiri::HTML5(html).at_css("[data-open-blog-content]")
      end
    end
  end
end
