require_relative "test_helper"

class IconsHelperTest < ActionView::TestCase
  tests OpenBlog::IconsHelper

  test "icons use local decorative SVG partials and reject unknown names" do
    %w[sun moon monitor share copy check link].each do |name|
      svg = Nokogiri::HTML5.fragment(open_blog_icon(name)).at_css("svg")
      assert svg, name
      assert_equal "true", svg["aria-hidden"]
      assert_equal "false", svg["focusable"]
      assert_empty svg.css("script, use[href^='http']")
    end
    assert_raises(ArgumentError) { open_blog_icon("../shared/header") }
  end
end
