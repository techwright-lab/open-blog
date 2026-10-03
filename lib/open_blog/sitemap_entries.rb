require "uri"

module OpenBlog
  class SitemapEntries
    def self.call(base_url: OpenBlog.config.public_base_url)
      raise ConfigurationError, "Set public_base_url or pass base_url to sitemap_entries" if base_url.blank?
      new(base_url).call
    end

    def initialize(base_url)
      unless base_url.is_a?(String)
        raise ConfigurationError, "Sitemap base_url must be an absolute HTTP(S) origin"
      end
      @origin = URI.parse(base_url)
      unless @origin.is_a?(URI::HTTP) && @origin.host.present? && @origin.userinfo.nil? &&
          [ "", "/" ].include?(@origin.path) && @origin.query.nil? && @origin.fragment.nil?
        raise ConfigurationError, "Sitemap base_url must be an absolute HTTP(S) origin"
      end
      @base_url = base_url.chomp("/")
    rescue URI::InvalidURIError
      raise ConfigurationError, "Sitemap base_url must be an absolute HTTP(S) origin"
    end

    def call
      featured = ReaderQueries.featured
      count = Post.listed.count - (featured ? 1 : 0)
      entries = list_pages(OpenBlog.mount_path, count)
      Post.listed.find_each do |post|
        next if off_site?(post.canonical_url)
        entry = { loc: post.url(base: @base_url) }
        date = ReaderDates.modified_at(post)
        entry[:lastmod] = date if date
        entries << entry
      end
      Page.published.find_each do |page|
        next if OpenBlog.config.policy_urls[page.kind.to_sym].present?
        entries << { loc: page.url(base: @base_url), lastmod: page.updated_at }
      end
      if OpenBlog.config.primary_list_type == :tags
        Tag.find_each do |tag|
          entries.concat(list_pages(ReaderQueries.tag_path(tag), tag.posts.listed.count))
        end
      else
        Category.find_each do |category|
          entries.concat(list_pages(ReaderQueries.category_path(category), category.posts.listed.count))
        end
      end
      entries
    end

    private

    def list_pages(path, count)
      total = [ (count.to_f / OpenBlog.config.posts_per_page).ceil, 1 ].max
      (1..total).map { |page| { loc: "#{@base_url}#{path}#{page > 1 ? "?page=#{page}" : ''}" } }
    end

    def off_site?(url)
      return false if url.blank?
      uri = URI.parse(url)
      uri.host&.downcase != @origin.host.downcase || uri.port != @origin.port
    rescue URI::InvalidURIError
      true
    end
  end
end
