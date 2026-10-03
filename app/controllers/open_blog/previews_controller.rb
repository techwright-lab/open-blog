module OpenBlog
  class PreviewsController < ActionController::Base
    include ReaderController
    before_action :preview_headers
    before_action :require_html

    def show
      @post = Post.find_by_preview_token(params[:token])
      raise NotFound unless @post && (@post.previewable? || @post.published?)
      return redirect_to(@post.path, status: :found) if @post.published?
      @related_posts = ReaderQueries.related(@post)
      @related_cache_key = ReaderQueries.related_cache_key(@post, @related_posts)
      page_context(:preview, record: @post, path: @post.path,
        breadcrumbs: [ { name: OpenBlog.config.blog_title, path: OpenBlog.mount_path }, { name: @post.title, path: @post.path } ])
      render "open_blog/posts/show"
    end

    private

    def preview_headers
      request.delete_header("HTTP_IF_NONE_MATCH")
      request.delete_header("HTTP_IF_MODIFIED_SINCE")
      response.headers["Cache-Control"] = "no-store"
      response.headers["X-Robots-Tag"] = "noindex, nofollow"
      response.headers["Referrer-Policy"] = "no-referrer"
    end

    def render_not_found
      preview_headers
      request.format = :html
      page_context(:preview_expired, path: "#{OpenBlog.mount_path.chomp('/')}/preview")
      render "open_blog/errors/preview_expired", status: :not_found, formats: [ :html ], content_type: "text/html"
    end
  end
end
