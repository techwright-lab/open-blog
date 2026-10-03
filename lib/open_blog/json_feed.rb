module OpenBlog
  class JsonFeed
    def initialize(posts:, base_url:, feed_path:, title:, category: nil)
      @posts, @base_url, @feed_path, @title, @category = posts, base_url.chomp("/"), feed_path, title, category
    end

    def to_h
      home_path = @category ? ReaderQueries.category_path(@category) : OpenBlog.mount_path
      { version: "https://jsonfeed.org/version/1.1", title: @title,
        home_page_url: "#{@base_url}#{home_path}", feed_url: "#{@base_url}#{@feed_path}",
        authors: [ { name: OpenBlog.config.publisher&.fetch(:name, nil) || OpenBlog.config.site_name } ],
        items: @posts.map { |post| item(post) } }
    end

    def to_json(*arguments)
      to_h.to_json(*arguments)
    end

    private

    def item(post)
      url = post.url(base: @base_url)
      entry = { id: url, url: url, title: post.title, summary: post.description,
        authors: [ { name: post.author_name, url: "#{@base_url}#{ReaderQueries.author_path(post.author)}" } ],
        date_modified: ReaderDates.feed_updated_at(post).iso8601 }
      published = ReaderDates.published_at(post)
      entry[:date_published] = published.iso8601 if published
      if OpenBlog.config.feed_content == :full
        entry[:content_html] = Renderer.render(post).to_s
      else
        entry[:content_text] = post.description
      end
      entry
    end
  end
end
