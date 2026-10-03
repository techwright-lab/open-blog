require "json"
require "rails"
require "commonmarker"
require "rouge"
require "mcp"

require_relative "open_blog/version"
require_relative "open_blog/instructions"

module OpenBlog
  FAQ_SELECTORS = { section: "[data-open-blog-faq]", entry: "[data-open-blog-faq-entry]" }.freeze

  autoload :Configuration, "open_blog/configuration"
  autoload :ConfigurationError, "open_blog/configuration_error"
  autoload :RevisionPayload, "open_blog/revision_payload"
  autoload :PlainText, "open_blog/plain_text"
  autoload :Result, "open_blog/result"
  autoload :Error, "open_blog/errors"
  autoload :PostIdentity, "open_blog/post_identity"
  autoload :PostAttributes, "open_blog/post_attributes"
  autoload :Operation, "open_blog/operation"
  autoload :WritePost, "open_blog/write_post"
  autoload :SaveDraft, "open_blog/save_draft"
  autoload :Publish, "open_blog/publish"
  autoload :Approve, "open_blog/approve"
  autoload :RedirectTarget, "open_blog/redirect_target"
  autoload :Remove, "open_blog/remove"
  autoload :Unpublish, "open_blog/unpublish"
  autoload :RecordRelease, "open_blog/record_release"
  autoload :ContentGuard, "open_blog/content_guard"
  autoload :RichTextGuard, "open_blog/rich_text_guard"
  autoload :PolicyUrl, "open_blog/policy_url"
  autoload :LabelPolicy, "open_blog/label_policy"
  autoload :Findings, "open_blog/findings"
  autoload :Adopt, "open_blog/adopt"
  autoload :FaqExtraction, "open_blog/faq_extraction"
  autoload :ImageFetch, "open_blog/image_fetch"
  autoload :ImageImport, "open_blog/image_import"
  autoload :ImageResolution, "open_blog/image_resolution"
  autoload :Renderer, "open_blog/renderer"
  autoload :SyntaxCss, "open_blog/syntax_css"
  autoload :BuildCss, "open_blog/build_css"
  autoload :ReaderPage, "open_blog/reader_page"
  autoload :ReaderDates, "open_blog/reader_dates"
  autoload :JsonFeed, "open_blog/json_feed"
  autoload :MarkdownView, "open_blog/markdown_view"
  autoload :ReaderQueries, "open_blog/reader_queries"
  autoload :Search, "open_blog/search"
  autoload :PageViews, "open_blog/page_views"
  autoload :Pagination, "open_blog/pagination"
  autoload :NotFound, "open_blog/not_found"
  autoload :SitemapEntries, "open_blog/sitemap_entries"
  autoload :SurfaceReport, "open_blog/surface_report"
  autoload :Doctor, "open_blog/doctor"
  autoload :Sample, "open_blog/sample"
  autoload :Actor, "open_blog/actor"
  autoload :Mcp, "open_blog/mcp"
  autoload :ApiFields, "open_blog/api_fields"
  autoload :Authentication, "open_blog/authentication"

  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield config
      config
    end

    def policy_url(kind, config: self.config)
      PolicyUrl.call(kind, config: config)
    end

    def sitemap_entries(base_url: config.public_base_url)
      SitemapEntries.call(base_url: base_url)
    end

    def mount_path
      application = Rails.application
      return config.mount_path unless application&.initialized?

      route = application.routes.routes.find do |candidate|
        candidate.app.respond_to?(:app) && candidate.app.app == Engine
      end
      route ? route.path.spec.to_s : config.mount_path
    end
  end
end

require_relative "open_blog/engine"
