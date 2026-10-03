module OpenBlog
  class PageSerializer
    def self.call(page, base_url: nil)
      { kind: page.kind, slug: page.slug, url: page.url(base: OpenBlog.config.public_base_url || base_url),
        title: page.title, body: page.body_markdown, status: page.status,
        approved_by: page.approved_by, approved_on: page.approved_on, updated_at: page.updated_at&.iso8601 }
    end
  end
end
