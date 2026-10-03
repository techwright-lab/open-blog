require_relative "test_helper"
require "minitest/mock"

class ThemeHelperTest < ActiveSupport::TestCase
  setup do
    @scheme = OpenBlog.config.color_scheme
    @view = ActionView::Base.empty
    @view.extend(OpenBlog::ThemeHelper)
    @view.define_singleton_method(:content_security_policy_nonce) { nil }
  end

  teardown { OpenBlog.config.color_scheme = @scheme }

  test "system boot script is nonce bearing and fixed modes use server attributes" do
    OpenBlog.config.color_scheme = :system
    @view.stub(:content_security_policy_nonce, "reader-nonce") do
      doc = Nokogiri::HTML5.fragment(@view.open_blog_theme_script)
      assert_equal "reader-nonce", doc.at_css("script")["nonce"]
      assert_includes doc.text, 'localStorage.getItem("open-blog-theme")'
      assert_includes doc.text, 'theme === "light" || theme === "dark"'
      assert_includes doc.text, "catch"
      assert_equal({}, @view.open_blog_theme_attributes)
    end
    %i[light dark].each do |scheme|
      OpenBlog.config.color_scheme = scheme
      assert_equal({ data: { theme: scheme.to_s } }, @view.open_blog_theme_attributes)
      assert_equal "", @view.open_blog_theme_script
      colors = Nokogiri::HTML5.fragment(@view.open_blog_theme_colors).css("meta").map { |node| node["content"] }
      assert_equal [ OpenBlog::ThemeHelper::SURFACES.fetch(scheme.to_s) ] * 2, colors
    end
  end

  test "theme colors expose the two supported system surfaces" do
    doc = Nokogiri::HTML5.fragment(@view.open_blog_theme_colors)
    assert_equal 2, doc.css('meta[name="theme-color"]').length
    assert_equal "#ffffff", doc.at_css('meta[media="(prefers-color-scheme: light)"]')["content"]
    assert_equal "#0f172a", doc.at_css('meta[media="(prefers-color-scheme: dark)"]')["content"]
  end

  test "stylesheets always load the built bundle and only include an existing host override" do
    calls = []
    @view.stub(:stylesheet_link_tag, ->(name) { calls << name; "<link>".html_safe }) do
      @view.stub(:open_blog_theme_override?, false) { @view.open_blog_stylesheets }
      assert_equal [ "open_blog/blog" ], calls
      calls.clear
      @view.stub(:open_blog_theme_override?, true) { @view.open_blog_stylesheets }
      assert_equal [ "open_blog/blog", "open_blog_theme" ], calls
    end
  end
end
