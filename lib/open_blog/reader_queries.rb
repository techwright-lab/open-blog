require "digest"
require "json"

module OpenBlog
  module ReaderQueries
    def self.posts
      Post.listed.includes(:author, :category, :tags, cover_image: { file_attachment: :blob }).order(Arel.sql("published_at IS NULL ASC"), published_at: :desc, id: :desc)
    end

    def self.featured
      posts.where(featured: true).first
    end

    def self.category_path(category)
      "#{OpenBlog.mount_path.chomp('/')}/#{OpenBlog.config.route_segments.fetch(:category)}/#{category.slug}"
    end

    def self.tag_path(tag)
      "#{OpenBlog.mount_path.chomp('/')}/#{OpenBlog.config.route_segments.fetch(:tag)}/#{tag.slug}"
    end

    def self.author_path(author)
      "#{OpenBlog.mount_path.chomp('/')}/#{OpenBlog.config.route_segments.fetch(:author)}/#{author.slug}"
    end

    def self.series_path(series)
      "#{OpenBlog.mount_path.chomp('/')}/#{OpenBlog.config.route_segments.fetch(:series)}/#{series.slug}"
    end

    def self.series_posts(series)
      posts.where(series_id: series.id).reorder(Arel.sql("series_position IS NULL ASC"), series_position: :asc, id: :asc)
    end

    def self.series_neighbors(post)
      return {} unless post.series_id
      scope = series_posts(post.series).where.not(id: post.id)
      if post.series_position
        previous = scope.where("series_position < ?", post.series_position).reverse_order.first
        following = scope.where("series_position > ? OR series_position IS NULL", post.series_position).first
      else
        previous = scope.where("series_position IS NOT NULL OR id < ?", post.id).reverse_order.first
        following = scope.where(series_position: nil).where("id > ?", post.id).first
      end
      { previous: previous, next: following }
    end

    def self.sidebar
      category_counts = Post.listed.where.not(category_id: nil).group(:category_id).count
      tag_counts = Tagging.joins(:post).merge(Post.listed).group(:tag_id).count
      categories = Category.where(id: category_counts.keys).order(:position, :name).map { |category| { category: category, count: category_counts.fetch(category.id) } }
      tags = Tag.where(id: tag_counts.keys).to_a.sort_by { |tag| [ -tag_counts.fetch(tag.id), tag.name, tag.id ] }.first(20).map { |tag| { tag: tag, count: tag_counts.fetch(tag.id) } }
      { categories: categories, tags: tags }
    end

    def self.sidebar_cache_key(sidebar)
      fields = sidebar[:categories].map { |entry| [ entry[:category].attributes.slice("id", "name", "slug", "position"), entry[:count] ] } +
        sidebar[:tags].map { |entry| [ entry[:tag].attributes.slice("id", "name", "slug"), entry[:count] ] }
      [ "open_blog/sidebar", Post.listed.maximum(:modified_at), Post.listed.count,
        OpenBlog.config.locale, OpenBlog.mount_path, Digest::SHA256.hexdigest(JSON.generate([ fields, OpenBlog.config.route_segments ])) ]
    end

    def self.related_cache_key(post, related)
      fields = related.map do |entry|
        [ entry.id, entry.current_revision_identifier, entry.slug, entry.author.slug, entry.author.avatar.blob&.key,
          entry.category&.attributes&.slice("name", "slug"), entry.cover_image&.path,
          ReaderDates.published_at(entry), ReaderDates.modified_at(entry), entry.reading_time_minutes ]
      end
      [ "open_blog/related", post.id, Post.listed.maximum(:modified_at), Post.listed.count,
        OpenBlog.config.locale, OpenBlog.mount_path, Digest::SHA256.hexdigest(JSON.generate([ fields, OpenBlog.config.route_segments ])) ]
    end

    def self.popular
      settings = OpenBlog.config.popular_posts
      return [] unless settings[:enabled]
      days, limit = settings.fetch(:days, 30), settings.fetch(:limit, 5)
      key = [ "open_blog/popular", days, limit, OpenBlog.config.locale, OpenBlog.mount_path, OpenBlog.config.route_segments ]
      ids = Rails.cache.fetch(key, expires_in: 1.hour) do
        PageViews.top(days: days, limit: limit, scope: Post.listed).fetch(:posts).map { |post| post.fetch(:id) }
      end
      current = Post.listed.where(id: ids).index_by(&:id)
      ids.filter_map { |id| current[id] }
    end

    def self.related(post)
      scope = posts.where.not(id: post.id)
      scope = scope.where(category_id: post.category_id) if post.category_id
      scope.limit(3).to_a
    end
  end
end
