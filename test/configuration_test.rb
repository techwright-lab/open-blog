require "minitest/autorun"
require "rails"
require "open_blog/configuration"

class ConfigurationTest < Minitest::Test
  DEFAULTS = {
    site_name: nil, public_base_url: nil, default_author: nil, publisher: nil,
    locale: I18n.default_locale, blog_title: "Blog", blog_tagline: nil,
    layout: "open_blog", parent_controller: "ActionController::Base", mount_path: "/blog",
    route_segments: { category: "category", tag: "tag", author: "author", series: "series" },
    posts_per_page: 12, primary_list_type: :categories, call_to_action: nil,
    default_social_image_url: nil,
    policy_urls: { responsible_party: nil, corrections: nil, editorial: nil, ai_use: nil },
    sign_in_destinations: nil, body_formats: [ :markdown ], default_body_format: :markdown,
    markdown_hardbreaks: true, ai_label: :when_required, require_approval: false,
    before_publish: nil, color_scheme: :system, syntax_theme: "github", feed_content: :summary,
    feed_size: 20, serve_sitemap: true, page_views: true, page_view_retention_days: nil,
    popular_posts: { enabled: false, days: 30, limit: 5 }, preview_expires_in: 7 * 24 * 60 * 60,
    storage_service: nil, image_delivery: :redirect, max_image_bytes: 10 * 1024 * 1024,
    image_content_types: %w[image/png image/jpeg image/webp image/gif image/avif],
    image_fetch_policy: :public_only, authenticate: nil,
    api_rate_limit: { to: 120, within: 60 }, search_rate_limit: { to: 30, within: 60 }
  }.freeze

  DEFAULTS.each do |key, expected|
    define_method("test_default_#{key}") do
      value = OpenBlog::Configuration.new.public_send(key)
      expected.nil? ? assert_nil(value) : assert_equal(expected, value)
    end
  end

  def test_default_title_suffix_tracks_site_name_until_overridden
    config = OpenBlog::Configuration.new
    config.site_name = "Example"
    assert_equal " — Example", config.title_suffix
    config.site_name = "Another"
    assert_equal " — Another", config.title_suffix
    config.title_suffix = ""
    config.site_name = "Changed"
    assert_equal "", config.title_suffix
  end

  def test_default_page_view_bot_pattern
    pattern = OpenBlog::Configuration.new.page_view_bot_pattern
    assert_instance_of Regexp, pattern
    %w[Googlebot Bingbot crawler spider slurp LinkPreview UptimeMonitor curl wget HeadlessChrome].each { |agent| assert_match pattern, agent }
    refute_match pattern, "Mozilla/5.0 Firefox/140.0"
  end

  def test_default_rate_limit_store_resolves_current_rails_cache
    original = Rails.cache
    config = OpenBlog::Configuration.new
    first, second = Object.new, Object.new
    Rails.cache = first
    assert_same first, config.rate_limit_store
    Rails.cache = second
    assert_same second, config.rate_limit_store
    config.rate_limit_store = first
    assert_same first, config.rate_limit_store
  ensure
    Rails.cache = original
  end

  def test_default_mcp_enabled
    assert_equal true, OpenBlog::Configuration.new.mcp.enabled
  end

  def test_mcp_rejects_invalid_enablement_and_page_limits
    config = OpenBlog::Configuration.new
    [ nil, 0, -1, "50", 1.5 ].each do |value|
      config.mcp.max_page_size = value
      assert_raises(OpenBlog::ConfigurationError) { config.validate_structure! }
    end
    config.mcp.max_page_size = 50
    config.mcp.enabled = "false"
    assert_raises(OpenBlog::ConfigurationError) { config.validate_structure! }
  end

  def test_default_mcp_max_page_size
    assert_equal 50, OpenBlog::Configuration.new.mcp.max_page_size
  end

  def test_mutable_defaults_are_not_shared
    first, second = OpenBlog::Configuration.new, OpenBlog::Configuration.new
    first.route_segments[:category].replace("topics")
    first.body_formats << :rich_text
    first.policy_urls[:editorial] = "/editorial"
    first.popular_posts[:enabled] = true
    first.api_rate_limit[:to] = 1
    first.search_rate_limit[:to] = 2
    first.image_content_types.first.replace("image/svg+xml")
    first.blog_title.replace("News")
    first.mcp.enabled = false
    assert_equal "category", second.route_segments[:category]
    assert_equal [ :markdown ], second.body_formats
    assert_nil second.policy_urls[:editorial]
    assert_equal false, second.popular_posts[:enabled]
    assert_equal 120, second.api_rate_limit[:to]
    assert_equal 30, second.search_rate_limit[:to]
    assert_equal "image/png", second.image_content_types.first
    assert_equal "Blog", second.blog_title
    assert_equal true, second.mcp.enabled
  end

  def test_required_identity_values_are_checked_individually
    %i[site_name default_author publisher].each do |key|
      config = valid_configuration
      config.public_send("#{key}=", nil)
      assert_invalid config, key
    end
  end

  def test_production_requires_public_base_url
    config = valid_configuration
    original = Rails.env
    Rails.env = "production"
    config.public_base_url = nil
    assert_invalid config, :public_base_url
    config.public_base_url = "https://example.com"
    assert_same config, config.validate!
    Rails.env = "development"
    config.public_base_url = nil
    assert_same config, config.validate!
  ensure
    Rails.env = original
  end

  def test_structural_validation_only_defers_missing_identity
    config = OpenBlog::Configuration.new
    assert_same config, config.validate_structure!
    assert_invalid config, :site_name
    config.site_name = " "
    assert_raises(OpenBlog::ConfigurationError) { config.validate_structure! }
  end

  def test_supplied_identity_is_validated
    {
      site_name: [ false, " " ],
      default_author: [ "Ada", {}, { name: "" }, { name: "Ada", type: :robot } ],
      publisher: [ "Example", {}, { name: " " } ],
      public_base_url: [ "example.com", "javascript:alert(1)", "https://example.com/path", "https://user:pass@example.com", "https://example.com?x=1" ]
    }.each do |key, values|
      values.each do |value|
        config = valid_configuration
        config.public_send("#{key}=", value)
        assert_invalid config, key
        assert_raises(OpenBlog::ConfigurationError) { config.validate_structure! }
      end
    end
  end

  def test_identity_urls_must_be_absolute_http_urls
    %i[default_author publisher].each do |key|
      config = valid_configuration
      config.public_send(key)[:url] = "javascript:alert(1)"
      assert_invalid config, key
    end
  end

  def test_body_formats_must_be_nonempty_known_formats
    [ nil, :markdown, [], [ :html ], [ :markdown, :html ] ].each do |formats|
      config = valid_configuration
      config.body_formats = formats
      assert_invalid config, :body_formats
      assert_raises(OpenBlog::ConfigurationError) { config.validate_structure! }
    end
  end

  def test_default_body_format_must_be_enabled
    config = valid_configuration
    config.default_body_format = :rich_text
    assert_invalid config, :default_body_format
    config.body_formats = [ :markdown, :rich_text ]
    assert_same config, config.validate!
  end

  def test_hook_setters_reject_incompatible_signatures_immediately
    config = valid_configuration
    {
      authenticate: [ -> { }, ->(a, b) { }, ->(request, required:) { }, Object.new ],
      before_publish: [ ->(post) { }, ->(a, b, c) { }, ->(post, context, required:) { }, false ]
    }.each do |key, values|
      values.each do |value|
        error = assert_raises(OpenBlog::ConfigurationError) { config.public_send("#{key}=", value) }
        assert_includes error.message, key.to_s
      end
    end
  end

  def test_hook_setters_accept_compatible_callables
    config = valid_configuration
    object = Class.new { def call(request); end }.new
    [ nil, ->(request) { }, ->(request, optional = nil) { }, ->(*args) { }, object, object.method(:call), proc { |request| } ].each do |hook|
      config.authenticate = hook
      assert_same hook, config.authenticate
    end
    [ nil, ->(post, context) { }, ->(post, context = nil) { }, ->(post, *rest) { }, ->(post, context, optional: nil) { } ].each do |hook|
      config.before_publish = hook
      assert_same hook, config.before_publish
    end
  end

  private

  def valid_configuration
    OpenBlog::Configuration.new.tap do |config|
      config.site_name = "Example"
      config.default_author = { name: "Ada", type: :person }
      config.publisher = { name: "Example Ltd", url: "https://example.com" }
    end
  end

  def assert_invalid(config, key)
    error = assert_raises(OpenBlog::ConfigurationError) { config.validate! }
    assert_includes error.message, key.to_s
  end
end
