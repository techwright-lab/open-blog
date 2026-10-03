module OpenBlog
  module HeadHelper
    include ThemeHelper

    def open_blog_lang
      OpenBlog.config.locale.to_s.tr("_", "-")
    end

    def open_blog_head(resource = nil)
      page = open_blog_page(resource)
      title = open_blog_page_title(page)
      description = open_blog_page_description(page)
      canonical = open_blog_canonical_url(page)
      tags = [ tag.title(title), tag.meta(name: "description", content: description), tag.link(rel: "canonical", href: canonical),
        tag.meta(name: "robots", content: open_blog_robots(page)), tag.meta(name: "viewport", content: "width=device-width, initial-scale=1"),
        tag.meta(property: "og:title", content: title), tag.meta(property: "og:description", content: description),
        tag.meta(property: "og:type", content: %i[post preview].include?(page.kind) ? "article" : "website"), tag.meta(property: "og:url", content: canonical),
        tag.meta(property: "og:site_name", content: OpenBlog.config.site_name), tag.meta(name: "twitter:card", content: "summary_large_image") ]
      image = open_blog_social_image_url(page)
      tags << tag.meta(property: "og:image", content: image) if image
      if %i[post preview].include?(page.kind)
        { published_time: ReaderDates.published_at(page.record), modified_time: ReaderDates.modified_at(page.record) }.each do |name, time|
          tags << tag.meta(property: "article:#{name}", content: time.iso8601) if time
        end
      end
      feed_path = page.kind == :category ? "#{page.path}/feed.xml" : "#{open_blog_index_path.chomp('/')}/feed.xml"
      tags << tag.link(rel: "alternate", type: "application/atom+xml", title: OpenBlog.config.blog_title, href: open_blog_absolute_url(feed_path, base: page.base_url))
      tags << open_blog_theme_colors
      safe_join(tags, "\n")
    end

    def open_blog_page_title(page = open_blog_page)
      title = case page.kind
      when :post, :preview then page.record.search_title.presence || page.record.title
      when :category, :author then page.record.name
      when :tag then open_blog_translate("titles.tag", name: page.record.name)
      when :not_found, :gone, :preview_expired then open_blog_translate("titles.#{page.kind}")
      else OpenBlog.config.blog_title
      end
      title = open_blog_translate("titles.page", title: title, page: page.page_number) if page.page_number > 1
      "#{title}#{OpenBlog.config.title_suffix}"
    end

    def open_blog_page_description(page = open_blog_page)
      record = page.record
      return record.search_description.presence || record.description.to_s if %i[post preview].include?(page.kind)
      paginated = page.page_number > 1
      if !paginated
        return OpenBlog.config.blog_tagline if page.kind == :index && OpenBlog.config.blog_tagline.present?
        return record.description if %i[category tag].include?(page.kind) && record.respond_to?(:description) && record.description.present?
        return record.bio if page.kind == :author && record.bio.present?
      end
      kind = %i[index category tag author].include?(page.kind) ? page.kind : :index
      open_blog_translate("descriptions.#{kind}#{'_page' if paginated}", site_name: OpenBlog.config.site_name, name: record&.try(:name), page: page.page_number)
    end

    def open_blog_robots(page = open_blog_page)
      return "noindex, nofollow" if %i[not_found gone preview preview_expired].include?(page.kind)
      return "index, follow" if %i[index post].include?(page.kind)
      primary = OpenBlog.config.primary_list_type.to_s.singularize.to_sym
      page.kind == primary ? "index, follow" : "noindex, follow"
    end

    def open_blog_social_image_url(page = open_blog_page)
      image = %i[post preview].include?(page.kind) && (page.record.social_image || page.record.cover_image)
      open_blog_absolute_url(image ? image.path : OpenBlog.config.default_social_image_url, base: page.base_url)
    end
  end
end
