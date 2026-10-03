module OpenBlog
  class FeedsController < ApplicationController
    def show
      scope = ReaderQueries.posts
      if params[:slug]
        @category = Category.find_by!(slug: params[:slug])
        scope = scope.where(category_id: @category.id)
      end
      @posts = scope.limit(OpenBlog.config.feed_size).to_a
      @base_url = origin.chomp("/")
      @feed_title = @category&.name || OpenBlog.config.blog_title
      @feed_updated_at = @posts.map { |post| ReaderDates.feed_updated_at(post) }.max || Time.current
      expires_in 1.hour, public: true
      if request.format.json?
        feed = JsonFeed.new(posts: @posts, base_url: @base_url, feed_path: request.path, title: @feed_title, category: @category)
        render body: feed.to_json, content_type: "application/feed+json"
      else
        render "open_blog/feeds/atom", formats: [ :xml ], content_type: "application/atom+xml", layout: false
      end
    end
  end
end
