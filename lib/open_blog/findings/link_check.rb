require "uri"

module OpenBlog
  module Findings
    class LinkCheck
      def code
        :link_same_site_broken
      end

      def call(post, context: {})
        document = context[:body_document] ||= Renderer.document(post)
        document.css("a[href]").map { |node| node["href"] }.uniq.filter_map do |href|
          path = local_path(href, post)
          next unless path && !resolves?(path)
          { code: code, rule: "T14", message: "Point this link to an available page.", location: href }
        end
      end

      private

      def local_path(href, post)
        return if href.blank? || href.start_with?("#", "?")
        reference = URI.parse(href)
        return if reference.scheme && !%w[http https].include?(reference.scheme.downcase)
        configured = OpenBlog.config.public_base_url
        return if (reference.host || reference.scheme) && configured.blank?
        origin = URI.parse(configured.presence || "https://open-blog.invalid")
        target = URI.join("#{origin.to_s.chomp('/')}#{post.path}", href)
        return unless [ target.scheme, target.host&.downcase, target.port ] == [ origin.scheme, origin.host&.downcase, origin.port ]
        mount = OpenBlog.mount_path.chomp("/")
        path = target.path
        return unless path == mount || path.start_with?("#{mount}/")
        relative = path.delete_prefix(mount)
        return if relative.match?(%r{\A/(?:api|mcp)(?:/|\z)})
        path
      rescue URI::InvalidURIError, URI::BadURIError
        nil
      end

      def resolves?(path)
        mount = OpenBlog.mount_path.chomp("/")
        route = Engine.routes.recognize_path(path.delete_prefix(mount).presence || "/", method: :get)
        format = route[:format].to_s
        controller = route[:controller].delete_prefix("open_blog/")
        case controller
        when "posts"
          return format.blank? || format == "html" if route[:action] == "index"
          return false unless format.blank? || %w[html md].include?(format)
          Post.listed.exists?(slug: route[:slug]) || Redirect.exists?(old_path: "#{mount}/#{route[:slug]}")
        when "categories", "tags", "authors", "series"
          return false unless format.blank? || format == "html"
          model = { "categories" => Category, "tags" => Tag, "authors" => Author, "series" => Series }.fetch(controller)
          model.exists?(slug: route[:slug])
        when "feeds"
          route[:slug].nil? || Category.exists?(slug: route[:slug])
        when "search"
          format.blank? || %w[html json].include?(format)
        when "sitemaps"
          OpenBlog.config.serve_sitemap
        when "pages"
          page = Page.published.find_by(slug: route[:slug])
          page && OpenBlog.config.policy_urls[page.kind.to_sym].blank?
        when "previews"
          return false unless format.blank? || format == "html"
          post = Post.find_by_preview_token(route[:token])
          post && (post.previewable? || post.published?)
        when "media"
          image = Image.find_by(sha256: route[:sha256])
          image && image.file.attached?
        else
          false
        end
      rescue ActionController::RoutingError
        false
      end
    end
  end
end
