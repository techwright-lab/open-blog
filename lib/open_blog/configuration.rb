require "rails"
require "i18n"
require "uri"
require "active_support/core_ext/numeric/time"
require "active_support/core_ext/numeric/bytes"
require "open_blog/configuration_error"

module OpenBlog
  class Configuration
    class Mcp
      attr_accessor :enabled, :max_page_size

      def initialize
        @enabled = true
        @max_page_size = 50
      end
    end

    attr_accessor :site_name, :public_base_url, :default_author, :publisher, :locale,
      :blog_title, :blog_tagline, :layout, :parent_controller, :mount_path,
      :route_segments, :posts_per_page, :primary_list_type, :call_to_action,
      :default_social_image_url, :policy_urls, :sign_in_destinations, :body_formats,
      :default_body_format, :markdown_hardbreaks, :ai_label, :require_approval,
      :color_scheme, :syntax_theme, :feed_content, :feed_size, :serve_sitemap,
      :page_views, :page_view_bot_pattern, :page_view_retention_days, :popular_posts,
      :preview_expires_in, :storage_service, :image_delivery, :max_image_bytes,
      :image_content_types, :image_fetch_policy, :api_rate_limit, :search_rate_limit
    attr_reader :mcp, :authenticate, :before_publish
    attr_writer :title_suffix, :rate_limit_store

    def initialize
      @locale = I18n.default_locale
      @blog_title = "Blog".dup
      @layout = "open_blog".dup
      @parent_controller = "ActionController::Base".dup
      @mount_path = "/blog".dup
      @route_segments = { category: "category", tag: "tag", author: "author", series: "series" }.transform_values(&:dup)
      @posts_per_page = 12
      @primary_list_type = :categories
      @policy_urls = { responsible_party: nil, corrections: nil, editorial: nil, ai_use: nil }
      @body_formats = [ :markdown ]
      @default_body_format = :markdown
      @markdown_hardbreaks = true
      @ai_label = :when_required
      @require_approval = false
      @color_scheme = :system
      @syntax_theme = "github".dup
      @feed_content = :summary
      @feed_size = 20
      @serve_sitemap = true
      @page_views = true
      @page_view_bot_pattern = /bot|crawler|spider|slurp|preview|monitor|curl|wget|headless/i
      @popular_posts = { enabled: false, days: 30, limit: 5 }
      @preview_expires_in = 7.days
      @image_delivery = :redirect
      @max_image_bytes = 10.megabytes
      @image_content_types = %w[image/png image/jpeg image/webp image/gif image/avif].map(&:dup)
      @image_fetch_policy = :public_only
      @api_rate_limit = { to: 120, within: 1.minute }
      @search_rate_limit = { to: 30, within: 1.minute }
      @mcp = Mcp.new
    end

    def title_suffix
      defined?(@title_suffix) ? @title_suffix : " — #{site_name}"
    end

    def rate_limit_store
      defined?(@rate_limit_store) ? @rate_limit_store : Rails.cache
    end

    def authenticate=(hook)
      validate_hook!(:authenticate, hook, 1)
      @authenticate = hook
    end

    def before_publish=(hook)
      validate_hook!(:before_publish, hook, 2)
      @before_publish = hook
    end

    def validate!
      %i[site_name default_author publisher].each do |key|
        invalid!(key, "is required") if public_send(key).nil?
      end
      invalid!(:public_base_url, "is required in production") if Rails.env.production? && public_base_url.nil?
      validate_structure!
    end

    def validate_structure!
      invalid!(:site_name, "must be a nonblank string") unless site_name.nil? || nonblank_string?(site_name)
      validate_identity!(:default_author, default_author)
      validate_identity!(:publisher, publisher)
      if default_author && !%i[person organization].include?(default_author[:type])
        invalid!(:default_author, "type must be :person or :organization")
      end
      validate_base_url! unless public_base_url.nil?
      unless body_formats.is_a?(Array) && body_formats.any? && (body_formats - %i[markdown rich_text]).empty?
        invalid!(:body_formats, "must be a nonempty array containing :markdown or :rich_text")
      end
      invalid!(:default_body_format, "must be enabled in body_formats") unless body_formats.include?(default_body_format)
      preview_duration
      invalid!(:mcp, "enabled must be true or false") unless [ true, false ].include?(mcp.enabled)
      invalid!(:mcp, "max_page_size must be a positive integer") unless mcp.max_page_size.is_a?(Integer) && mcp.max_page_size.positive?
      self
    end

    def preview_duration
      value = preview_expires_in
      unless (value.is_a?(Numeric) || value.is_a?(ActiveSupport::Duration)) && value.to_f.finite? && value.to_f.positive?
        invalid!(:preview_expires_in, "must be a positive finite duration")
      end
      value.to_f
    end

    private

    def validate_identity!(key, identity)
      return if identity.nil?
      unless identity.is_a?(Hash) && nonblank_string?(identity[:name])
        invalid!(key, "must be a hash with a nonblank name")
      end
      %i[url logo_url].each do |field|
        next if identity[field].nil?
        invalid!(key, "#{field} must be an absolute HTTP(S) URL") unless http_url?(identity[field])
      end
    end

    def validate_base_url!
      unless http_url?(public_base_url)
        invalid!(:public_base_url, "must be an absolute HTTP(S) origin")
      end
      uri = URI.parse(public_base_url)
      unless [ "", "/" ].include?(uri.path) && uri.query.nil? && uri.fragment.nil?
        invalid!(:public_base_url, "must contain only the scheme, host and optional port")
      end
    end

    def http_url?(value)
      return false unless value.is_a?(String)
      uri = URI.parse(value)
      uri.is_a?(URI::HTTP) && !uri.host.to_s.empty? && uri.userinfo.nil?
    rescue URI::InvalidURIError
      false
    end

    def nonblank_string?(value)
      value.is_a?(String) && !value.strip.empty?
    end

    def validate_hook!(name, hook, argument_count)
      return if hook.nil?
      invalid!(name, "must be callable") unless hook.respond_to?(:call)
      parameters = hook.is_a?(Proc) || hook.is_a?(Method) ? hook.parameters : hook.method(:call).parameters
      required = parameters.count { |kind, _| kind == :req }
      capacity = parameters.count { |kind, _| %i[req opt].include?(kind) }
      rest = parameters.any? { |kind, _| kind == :rest }
      keywords = parameters.any? { |kind, _| kind == :keyreq }
      unless required <= argument_count && (rest || capacity >= argument_count) && !keywords
        invalid!(name, "must accept #{argument_count} positional arguments without required keywords")
      end
    end

    def invalid!(name, message)
      raise ConfigurationError, "OpenBlog #{name} #{message}"
    end
  end
end
