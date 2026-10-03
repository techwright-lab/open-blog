module OpenBlog
  module PaginationHelper
    def open_blog_paginate(pagination = nil)
      page = open_blog_page
      pagination ||= page.pagination
      return "".html_safe unless pagination && pagination.total_pages > 1
      links = (1..pagination.total_pages).map do |number|
        if number == pagination.page
          tag.span(number, class: "ob-pagination-current", aria: { current: "page" })
        else
          path = page.path_for(number)
          link_to(number, path, class: "ob-pagination-link", aria: { label: open_blog_translate("navigation.page", page: number) })
        end
      end
      tag.nav(safe_join(links, " "), class: "ob-pagination", aria: { label: open_blog_translate("navigation.pagination") })
    end
  end
end
