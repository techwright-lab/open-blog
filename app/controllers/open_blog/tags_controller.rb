module OpenBlog
  class TagsController < ApplicationController
    before_action :require_html

    def show
      @tag = Tag.find_by!(slug: params[:slug])
      pagination = paginate(ReaderQueries.posts.where(id: Tagging.where(tag_id: @tag.id).select(:post_id)))
      @posts = pagination.records
      load_sidebar
      path = ReaderQueries.tag_path(@tag)
      page_context(:tag, record: @tag, path: path, pagination: pagination,
        breadcrumbs: [ { name: OpenBlog.config.blog_title, path: OpenBlog.mount_path }, { name: @tag.name, path: path } ])
    end
  end
end
