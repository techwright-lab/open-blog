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
      render "open_blog/feeds/atom", formats: [ :xml ], content_type: "application/atom+xml", layout: false
    end
  end
end
