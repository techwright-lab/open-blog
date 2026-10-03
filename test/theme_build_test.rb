require_relative "test_helper"
require "tmpdir"
require "minitest/mock"

class ThemeBuildTest < ActiveSupport::TestCase
  test "the committed stylesheet and token override rebuild byte for byte" do
    Dir.mktmpdir do |directory|
      output = File.join(directory, "blog.css")
      tokens = File.join(directory, "tokens.css")
      OpenBlog::BuildCss.write(path: output, tokens_path: tokens)
      assert_equal File.binread(OpenBlog::Engine.root.join("app/assets/builds/open_blog/blog.css")), File.binread(output)
      assert_equal File.binread(OpenBlog::Engine.root.join("lib/generators/open_blog/install/templates/theme/open_blog_theme.css")), File.binread(tokens)
      assert_includes File.read(output), ".ob-post-grid"
      assert_includes File.read(output), "prefers-color-scheme:dark"
      refute_includes File.read(output), OpenBlog::Engine.root.to_s
    end
  end

  test "build inputs are explicit and independent of the working directory and runtime Rouge" do
    original = Dir.pwd
    Dir.mktmpdir do |directory|
      File.write(File.join(directory, "noise.html"), '<p class="bg-fuchsia-950">Unrelated</p>')
      Dir.chdir(directory)
      OpenBlog::SyntaxCss.stub(:render, ->(*) { flunk "build must consume the committed syntax source" }) do
        css = OpenBlog::BuildCss.render
        assert_equal File.binread(OpenBlog::Engine.root.join("app/assets/builds/open_blog/blog.css")), css
        refute_includes css, ".bg-fuchsia-950"
      end
    end
  ensure
    Dir.chdir(original)
  end

  test "the host override contains only namespaced tokens" do
    names = OpenBlog::BuildCss.tokens.scan(/([\w-]+)\s*:\s*[^;{}]+;/).flatten
    assert names.any?
    assert_empty names.reject { |name| name.start_with?("--ob-") }
  end

  test "both themes define the same tokens and meet text contrast requirements" do
    source = File.read(OpenBlog::Engine.root.join("lib/generators/open_blog/install/templates/theme/theme.css"))
    light = declarations(source.match(/:root\s*\{([^}]+)\}/m)[1])
    dark = declarations(source.match(/:root\[data-theme="dark"\]\s*\{([^}]+)\}/m)[1])
    system = declarations(source.match(/:root:not\(\[data-theme="light"\]\)\s*\{([^}]+)\}/m)[1])
    assert_equal dark.except("color-scheme"), system.except("color-scheme")
    assert_empty dark.keys - light.keys
    %w[--ob-surface --ob-heading --ob-text --ob-text-muted --ob-text-subtle --ob-accent --ob-code-bg --ob-notice-text].each do |name|
      assert light[name], "missing light #{name}"
      assert dark[name], "missing dark #{name}"
    end
    [ light, light.merge(dark) ].each do |tokens|
      %w[--ob-surface --ob-surface-raised --ob-surface-sunken].each do |background|
        %w[--ob-heading --ob-text --ob-text-muted --ob-text-subtle --ob-accent --ob-accent-hover].each do |foreground|
          assert_contrast tokens.fetch(foreground), tokens.fetch(background), "#{foreground} on #{background}"
        end
      end
      %w[--ob-heading --ob-text --ob-text-muted --ob-accent].each do |foreground|
        assert_contrast tokens.fetch(foreground), tokens.fetch("--ob-accent-soft"), "#{foreground} on accent soft"
      end
      assert_contrast tokens.fetch("--ob-text-subtle"), tokens.fetch("--ob-code-bg"), "code language label"
      assert_contrast tokens.fetch("--ob-accent-contrast"), tokens.fetch("--ob-accent"), "accent control"
      assert_contrast tokens.fetch("--ob-notice-text"), tokens.fetch("--ob-notice-bg"), "notice"
      %w[--ob-note --ob-tip --ob-warning].each { |foreground| assert_contrast tokens.fetch(foreground), tokens.fetch("--ob-surface-raised"), foreground }
    end
  end

  test "theme color metadata follows the canonical default surfaces" do
    source = File.read(OpenBlog::Engine.root.join("lib/generators/open_blog/install/templates/theme/theme.css"))
    light = declarations(source.match(/:root\s*\{([^}]+)\}/m)[1])
    dark = declarations(source.match(/:root\[data-theme="dark"\]\s*\{([^}]+)\}/m)[1])
    previous = OpenBlog.config.color_scheme
    OpenBlog.config.color_scheme = :system
    view = ActionView::Base.empty.extend(OpenBlog::ThemeHelper)
    tags = Nokogiri::HTML5.fragment(view.open_blog_theme_colors).css('meta[name="theme-color"]')
    assert_equal 2, tags.length
    assert_equal light.fetch("--ob-surface"), tags.find { |tag| tag["media"].include?("light") }["content"]
    assert_equal dark.fetch("--ob-surface"), tags.find { |tag| tag["media"].include?("dark") }["content"]
  ensure
    OpenBlog.config.color_scheme = previous
  end

  test "every effective GitHub syntax text color meets normal code contrast in both themes" do
    generated = OpenBlog::SyntaxCss.render(theme: "github")
    packaged = File.read(OpenBlog::Engine.root.join("lib/generators/open_blog/install/templates/theme/syntax.css"))
    [ generated, packaged ].each { |css| assert_syntax_contrast(css) }
  end

  test "copied views contain no literal colors or unprefixed palette utilities" do
    Dir[OpenBlog::Engine.root.join("lib/generators/open_blog/install/templates/views/**/*")].select { |path| File.file?(path) }.each do |path|
      source = File.read(path)
      refute_match(/#[0-9a-f]{3,8}\b|rgba?\(|hsla?\(|\b(?:text|bg|border)-(?:slate|gray|red|blue|green|white|black)(?:-\d+)?\b/i, source, path)
    end
  end

  private

  def assert_syntax_contrast(css)
    colors = { light: {}, dark: {} }
    css.scan(/([^{}]+)\{([^{}]*)\}/m).each do |selector_group, body|
      values = declarations(body)
      next unless values["color"] || values["background-color"]
      selector_group.split(",").each do |selector|
        selector = selector.strip
        mode = selector.include?("data-theme") ? :dark : :light
        selector = selector.sub(/\A(?:\[data-theme="dark"\]|html:not\(\[data-theme="light"\]\))\s+/, "")
        colors[mode][selector] ||= {}
        colors[mode][selector].merge!(values)
      end
    end
    colors.each do |mode, rules|
      base = rules.fetch(".ob-highlight")
      assert_operator rules.length, :>, 25
      rules.each do |selector, values|
        assert_contrast values.fetch("color", base.fetch("color")), values.fetch("background-color", base.fetch("background-color")), "#{mode} #{selector}"
      end
    end
  end

  def declarations(source)
    source.scan(/([\w-]+)\s*:\s*([^;{}]+)\s*;/).to_h.transform_values(&:strip)
  end

  def assert_contrast(foreground, background, label)
    levels = [ foreground, background ].map { |color| luminance(color) }.sort
    ratio = (levels[1] + 0.05) / (levels[0] + 0.05)
    assert_operator ratio, :>=, 4.5, "#{label}: #{foreground} on #{background} gives #{ratio.round(3)}"
  end

  def luminance(color)
    assert_match(/\A#[0-9a-f]{6}\z/i, color)
    linear = color.delete_prefix("#").scan(/../).map do |channel|
      value = channel.to_i(16) / 255.0
      value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
    end
    linear.zip([ 0.2126, 0.7152, 0.0722 ]).sum { |value, weight| value * weight }
  end
end
