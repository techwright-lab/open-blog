module OpenBlog
  class PagesController < ApplicationController
    before_action :require_html

    def show
      @page = Page.published.find_by!(slug: params[:slug])
      raise NotFound if OpenBlog.config.policy_urls[@page.kind.to_sym].present?
      page_context(:page, record: @page, path: @page.path,
        breadcrumbs: [ { name: OpenBlog.config.blog_title, path: OpenBlog.mount_path }, { name: @page.title, path: @page.path } ])
    end
  end
end
