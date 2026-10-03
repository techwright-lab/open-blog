module OpenBlog
  class SeriesController < ApplicationController
    before_action :require_html

    def show
      @series = Series.find_by!(slug: params[:slug])
      pagination = paginate(ReaderQueries.series_posts(@series))
      @posts = pagination.records
      load_sidebar
      path = ReaderQueries.series_path(@series)
      page_context(:series, record: @series, path: path, pagination: pagination,
        breadcrumbs: [ { name: OpenBlog.config.blog_title, path: OpenBlog.mount_path }, { name: @series.name, path: path } ])
    end
  end
end
