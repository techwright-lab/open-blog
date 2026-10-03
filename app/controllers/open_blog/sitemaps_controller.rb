module OpenBlog
  class SitemapsController < ApplicationController
    def show
      raise NotFound unless OpenBlog.config.serve_sitemap
      @entries = OpenBlog.sitemap_entries(base_url: origin)
      expires_in 1.hour, public: true
      render "open_blog/sitemaps/show", formats: [ :xml ], content_type: "application/xml", layout: false
    end
  end
end
