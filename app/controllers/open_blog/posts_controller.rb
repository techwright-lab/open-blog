module OpenBlog
  class PostsController < ApplicationController
    before_action :require_html

    def index
      @featured = ReaderQueries.featured
      scope = ReaderQueries.posts
      scope = scope.where.not(id: @featured.id) if @featured
      pagination = paginate(scope)
      @posts = pagination.records
      load_sidebar
      page_context(:index, path: OpenBlog.mount_path, pagination: pagination,
        breadcrumbs: [ { name: OpenBlog.config.blog_title, path: OpenBlog.mount_path } ])
    end

    def show
      @post = ReaderQueries.posts.find_by(slug: params[:slug])
      unless @post
        redirect = Redirect.find_by(old_path: "#{OpenBlog.mount_path.chomp('/')}/#{params[:slug]}")
        raise NotFound unless redirect
        return redirect_to(redirect.new_path, status: :moved_permanently, allow_other_host: true) if redirect.new_path
        @posts = ReaderQueries.posts.limit(6).to_a
        page_context(:gone, path: request.path)
        return render "open_blog/errors/not_found", status: :gone
      end
      @related_posts = ReaderQueries.related(@post)
      @related_cache_key = ReaderQueries.related_cache_key(@post, @related_posts)
      crumbs = [ { name: OpenBlog.config.blog_title, path: OpenBlog.mount_path } ]
      crumbs << { name: @post.category.name, path: ReaderQueries.category_path(@post.category) } if @post.category
      crumbs << { name: @post.title, path: @post.path }
      page_context(:post, record: @post, path: @post.path, breadcrumbs: crumbs)
    end
  end
end
