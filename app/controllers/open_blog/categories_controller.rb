module OpenBlog
  class CategoriesController < ApplicationController
    before_action :require_html

    def show
      @category = Category.find_by!(slug: params[:slug])
      pagination = paginate(ReaderQueries.posts.where(category_id: @category.id))
      @posts = pagination.records
      load_sidebar
      path = ReaderQueries.category_path(@category)
      page_context(:category, record: @category, path: path, pagination: pagination,
        breadcrumbs: [ { name: OpenBlog.config.blog_title, path: OpenBlog.mount_path }, { name: @category.name, path: path } ])
    end
  end
end
