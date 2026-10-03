module OpenBlog
  module ReaderController
    extend ActiveSupport::Concern

    included do
      helper :all
      layout -> { OpenBlog.config.layout }
      around_action :use_blog_locale
      rescue_from OpenBlog::NotFound, ActiveRecord::RecordNotFound, with: :render_not_found
    end

    private

    def use_blog_locale(&block)
      I18n.with_locale(OpenBlog.config.locale, &block)
    end

    def require_html
      raise NotFound if params[:format].present? && params[:format] != "html"
      request.format = :html
    end

    def origin
      OpenBlog.config.public_base_url || request.base_url
    end

    def page_context(kind, path:, record: nil, pagination: nil, breadcrumbs: [])
      @open_blog_page = ReaderPage.new(kind: kind, path: path, base_url: origin, record: record, pagination: pagination, breadcrumbs: breadcrumbs)
    end

    def paginate(scope)
      Pagination.page(scope, page: params[:page], per_page: OpenBlog.config.posts_per_page)
    end

    def load_sidebar
      sidebar = ReaderQueries.sidebar
      @sidebar_categories, @sidebar_tags = sidebar.values_at(:categories, :tags)
      @sidebar_cache_key = ReaderQueries.sidebar_cache_key(sidebar) + [ controller_name, params[:slug] ]
    end

    def render_not_found
      request.format = :html
      @posts = ReaderQueries.posts.limit(6).to_a
      page_context(:not_found, path: request.path)
      render "open_blog/errors/not_found", status: :not_found, formats: [ :html ], content_type: "text/html"
    end
  end
end
