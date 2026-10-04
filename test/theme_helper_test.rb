require_relative "test_helper"
require "minitest/mock"

class ThemeHelperTest < ActiveSupport::TestCase
  setup do
    @original = OpenBlog.config
    OpenBlog.instance_variable_set(:@config, @original.deep_dup)
    @view = ActionView::Base.empty
    @view.extend(OpenBlog::ThemeHelper)
    @view.define_singleton_method(:content_security_policy_nonce) { nil }
    @view.define_singleton_method(:stylesheet_link_tag) { |name| tag.link(rel: "stylesheet", href: name) }
    @view.define_singleton_method(:open_blog_theme_override?) { false }
  end

  teardown { OpenBlog.instance_variable_set(:@config, @original) }

  test "system boot script is nonce bearing and fixed modes use server attributes" do
    OpenBlog.config.color_scheme = :system
    @view.stub(:content_security_policy_nonce, "reader-nonce") do
      doc = Nokogiri::HTML5.fragment(@view.open_blog_theme_script)
      assert_equal "reader-nonce", doc.at_css("script")["nonce"]
      assert_includes doc.text, 'localStorage.getItem("open-blog-theme")'
      assert_includes doc.text, 'theme === "light" || theme === "dark"'
      assert_includes doc.text, "catch"
      assert_equal({ data: { ob_theme: "signal" } }, @view.open_blog_theme_attributes)
    end
    surfaces = OpenBlog::Themes.fetch(:signal)
    %i[light dark].each do |scheme|
      OpenBlog.config.color_scheme = scheme
      assert_equal({ data: { theme: scheme.to_s, ob_theme: "signal" } }, @view.open_blog_theme_attributes)
      assert_equal "", @view.open_blog_theme_script
      assert_equal [ surfaces.public_send(scheme).fetch("surface") ] * 2, theme_colors.values
    end
  end

  test "the html element names the active preset and no preset for none" do
    OpenBlog::Themes.names.each do |name|
      OpenBlog.config.theme = name
      html = Nokogiri::HTML5(@view.tag.html(**@view.open_blog_theme_attributes)).at_css("html")
      assert_equal name.to_s, html["data-ob-theme"]
      assert_nil html["data-theme"]
    end
    OpenBlog.config.theme = :none
    assert_equal({}, @view.open_blog_theme_attributes)
    OpenBlog.config.color_scheme = :dark
    assert_equal({ data: { theme: "dark" } }, @view.open_blog_theme_attributes)
  end

  test "theme colors follow the surface of the active preset with overrides applied" do
    OpenBlog::Themes.names.each do |name|
      OpenBlog.config.theme = name
      preset = OpenBlog::Themes.fetch(name)
      assert_equal({ "(prefers-color-scheme: light)" => preset.light.fetch("surface"), "(prefers-color-scheme: dark)" => preset.dark.fetch("surface") }, theme_colors)
    end
    assert_equal "#000000", theme_colors.fetch("(prefers-color-scheme: dark)")
    OpenBlog.config.theme_colors = { surface: "#fefefe", dark: { surface: "#101010" } }
    assert_equal [ "#fefefe", "#101010" ], theme_colors.values
    OpenBlog.config.theme_colors = { light: { surface: "#fefefe" } }
    assert_equal [ "#fefefe", "#000000" ], theme_colors.values
    OpenBlog.config.theme = :none
    assert_equal [ "#ffffff", "#0f172a" ], theme_colors.values
  end

  test "stylesheets load the presets first then the bundle and an existing host override" do
    assert_equal [ "open_blog/themes", "open_blog/blog" ], stylesheets.css("link").map { |node| node["href"] }
    assert_empty stylesheets.css("style")
    @view.stub(:open_blog_theme_override?, true) do
      assert_equal [ "open_blog/themes", "open_blog/blog", "open_blog_theme" ], stylesheets.css("link").map { |node| node["href"] }
    end
    OpenBlog.config.theme = :none
    OpenBlog.config.theme_colors = { accent: "#1d4ed8" }
    assert_equal [ "open_blog/blog" ], stylesheets.css("link").map { |node| node["href"] }
    assert_empty stylesheets.css("style")
    assert_equal "", @view.open_blog_theme_stylesheets
  end

  test "colour overrides follow every stylesheet in one nonce bearing style element" do
    OpenBlog.config.theme = :editorial
    OpenBlog.config.theme_colors = { accent: "#1d4ed8", accent_2: "#b7791f", dark: { accent: "#93c5fd" } }
    @view.stub(:content_security_policy_nonce, "reader-nonce") do
      @view.stub(:open_blog_theme_override?, true) do
        doc = stylesheets
        assert_equal %w[link link link style], doc.element_children.map(&:name)
        style = doc.css("style").sole
        assert_equal "reader-nonce", style["nonce"]
        assert_equal <<~CSS, style.text
          :root[data-ob-theme="editorial"] {
            --ob-accent: #1d4ed8;
            --ob-accent-2: #b7791f;
          }
          :root[data-ob-theme="editorial"][data-theme="dark"] {
            --ob-accent: #93c5fd;
            --ob-accent-2: #b7791f;
          }
          @media (prefers-color-scheme: dark) {
            :root[data-ob-theme="editorial"]:not([data-theme="light"]) {
              --ob-accent: #93c5fd;
              --ob-accent-2: #b7791f;
            }
          }
        CSS
        assert_equal OpenBlog::Themes.css(:editorial, light: OpenBlog.config.theme_colors_for(:light), dark: OpenBlog.config.theme_colors_for(:dark)), style.text
        partial = Nokogiri::HTML5.fragment(@view.open_blog_theme_stylesheets)
        assert_equal [ "open_blog/themes" ], partial.css("link").map { |node| node["href"] }
        assert_equal style.text, partial.css("style").sole.text
      end
    end
    assert_nil stylesheets.at_css("style")["nonce"]
    OpenBlog.config.theme_colors = { light: { surface: "#fefefe" } }
    refute_includes stylesheets.at_css("style").text, "dark"
  end

  test "a value changed after boot is refused instead of reaching the page" do
    OpenBlog.config.theme_colors = { accent: "#fff} </style><script>alert(1)</script>" }
    assert_raises(OpenBlog::ConfigurationError) { @view.open_blog_stylesheets }
    assert_raises(OpenBlog::ConfigurationError) { @view.open_blog_theme_colors }
    OpenBlog.config.theme_colors = {}
    OpenBlog.config.theme = :"signal\"]{} </style><script>alert(1)</script>"
    assert_raises(OpenBlog::ConfigurationError) { @view.open_blog_stylesheets }
    assert_raises(OpenBlog::ConfigurationError) { @view.open_blog_theme_attributes }
  end

  private

  def stylesheets
    Nokogiri::HTML5.fragment(@view.open_blog_stylesheets)
  end

  def theme_colors
    Nokogiri::HTML5.fragment(@view.open_blog_theme_colors).css('meta[name="theme-color"]').to_h { |node| [ node["media"], node["content"] ] }
  end
end
