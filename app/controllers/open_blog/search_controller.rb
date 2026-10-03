module OpenBlog
  class SearchController < ApplicationController
    before_action :limit_search_requests

    def show
      raise NotFound if params[:format].present? && !%w[html json].include?(params[:format])
      response.headers["X-Robots-Tag"] = "noindex"
      @query = params[:q].is_a?(String) ? params[:q].strip : ""
      scope = Search.call(@query, scope: ReaderQueries.posts)
      if params[:format] == "json"
        render json: scope.limit(8).map { |post| { title: post.title, url: post.url(base: origin), description: post.description } }
      else
        request.format = :html
        pagination = paginate(scope)
        @posts = pagination.records
        load_sidebar
        path = "#{OpenBlog.mount_path.chomp('/')}/search?#{ { q: @query }.to_query }"
        page_context(:search, path: path, pagination: pagination,
          breadcrumbs: [ { name: OpenBlog.config.blog_title, path: OpenBlog.mount_path }, { name: I18n.t("open_blog.search.heading"), path: path } ])
      end
    end

    private

    def limit_search_requests
      options = { to: OpenBlog.config.search_rate_limit.fetch(:to), within: OpenBlog.config.search_rate_limit.fetch(:within),
        by: -> { request.remote_ip }, with: -> { head :too_many_requests }, store: OpenBlog.config.rate_limit_store, name: nil }
      options[:scope] = "open_blog/search" if method(:rate_limiting).parameters.any? { |kind, name| kind == :keyreq && name == :scope }
      rate_limiting(**options)
    end
  end
end
