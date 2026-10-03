require "uri"

module OpenBlog
  module UrlHelper
    def open_blog_index_path
      OpenBlog.mount_path.chomp("/").presence || "/"
    end

    def open_blog_list_path(kind, record)
      segment = OpenBlog.config.route_segments.fetch(kind.to_s.singularize.to_sym)
      "#{open_blog_index_path.chomp('/')}/#{segment}/#{record.slug}"
    end

    def open_blog_page(resource = nil)
      return resource if resource.is_a?(ReaderPage)
      return @open_blog_page if @open_blog_page && (resource.nil? || resource == @open_blog_page.record)
      kind = case resource
      when Post then :post
      when Page then :page
      when Category then :category
      when Tag then :tag
      when Author then :author
      when Series then :series
      else :index
      end
      path = if %i[post page].include?(kind)
        resource.path
      elsif resource
        open_blog_list_path(kind, resource)
      else
        open_blog_index_path
      end
      crumbs = [ { name: OpenBlog.config.blog_title, path: open_blog_index_path } ]
      crumbs << { name: %i[post page].include?(kind) ? resource.title : resource.name, path: path } if resource
      ReaderPage.new(kind: kind, record: resource, path: path, base_url: OpenBlog.config.public_base_url || request.base_url, breadcrumbs: crumbs)
    end

    def open_blog_absolute_url(path, base: nil)
      return if path.blank?
      base ||= @open_blog_page&.base_url || OpenBlog.config.public_base_url
      base ||= request.base_url if respond_to?(:request) && request
      uri = URI.join("#{base.to_s.chomp('/')}/", path.to_s)
      uri.to_s if uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil?
    rescue URI::InvalidURIError
      nil
    end

    def open_blog_canonical_url(resource = nil)
      page = open_blog_page(resource)
      path = %i[post preview].include?(page.kind) && page.record.canonical_url.presence || page.canonical_path
      open_blog_absolute_url(path, base: page.base_url)
    end

    def open_blog_translate(key, **options)
      I18n.t("open_blog.#{key}", locale: OpenBlog.config.locale, **options)
    end
  end
end
