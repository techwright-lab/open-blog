module OpenBlog
  class AuthorsController < ApplicationController
    before_action :require_html

    def show
      @author = Author.find_by!(slug: params[:slug])
      pagination = paginate(ReaderQueries.posts.where(author_id: @author.id))
      @posts = pagination.records
      path = ReaderQueries.author_path(@author)
      page_context(:author, record: @author, path: path, pagination: pagination,
        breadcrumbs: [ { name: OpenBlog.config.blog_title, path: OpenBlog.mount_path }, { name: @author.name, path: path } ])
    end
  end
end
