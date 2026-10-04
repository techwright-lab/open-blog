require_relative "test_helper"
require "tmpdir"
require "minitest/mock"

class ThemeBuildTest < ActiveSupport::TestCase
  test "the committed stylesheets and the override stub rebuild byte for byte" do
    Dir.mktmpdir do |directory|
      output = File.join(directory, "blog.css")
      tokens = File.join(directory, "tokens.css")
      themes = File.join(directory, "themes.css")
      OpenBlog::BuildCss.write(path: output, tokens_path: tokens, themes_path: themes)
      assert_equal File.binread(OpenBlog::Engine.root.join("app/assets/builds/open_blog/blog.css")), File.binread(output)
      assert_equal File.binread(OpenBlog::Engine.root.join("app/assets/builds/open_blog/themes.css")), File.binread(themes)
      assert_equal File.binread(theme_source("open_blog_theme.css")), File.binread(tokens)
      assert_includes File.read(output), ".ob-post-grid"
      assert_includes File.read(output), "prefers-color-scheme:dark"
      refute_includes File.read(output), OpenBlog::Engine.root.to_s
    end
  end

  test "a custom output path keeps the preset stylesheet beside it" do
    Dir.mktmpdir do |directory|
      OpenBlog::BuildCss.write(path: File.join(directory, "out/blog.css"), tokens_path: File.join(directory, "tokens.css"))
      assert_equal OpenBlog::BuildCss.themes, File.read(File.join(directory, "out/themes.css"))
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

  test "the host override is a commented example of namespaced tokens" do
    stub = OpenBlog::BuildCss.tokens
    assert_empty stub.gsub(%r{/\*.*?\*/}m, "").strip
    assert_includes stub, ":root[data-ob-theme] {"
    names = stub.scan(/([\w-]+)\s*:\s*[^;{}]+;/).flatten
    assert names.any?
    assert_empty names.reject { |name| name.start_with?("--ob-") }
  end

  test "the preset stylesheet holds every preset in light, dark and system dark" do
    css = OpenBlog::BuildCss.themes
    assert_equal OpenBlog::Themes.names, css.scan(/^:root\[data-ob-theme="(\w+)"\] \{/).flatten.map(&:to_sym)
    OpenBlog::Themes.names.each do |name|
      preset = OpenBlog::Themes.fetch(name)
      root = %(:root[data-ob-theme="#{name}"])
      light = declarations(css[/^#{Regexp.escape(root)} \{(.*?)^\}/m, 1])
      dark = declarations(css[/^#{Regexp.escape(root)}\[data-theme="dark"\] \{(.*?)^\}/m, 1])
      system = declarations(css[/^  #{Regexp.escape(root)}:not\(\[data-theme="light"\]\) \{(.*?)^  \}/m, 1])
      assert_equal preset.light.merge(preset.tokens).transform_keys { |token| "--ob-#{token}" }, light
      assert_equal preset.dark.transform_keys { |token| "--ob-#{token}" }, dark
      assert_equal dark, system
    end
    assert_includes css, ":root { color-scheme: light dark; }"
    assert_operator css.index("@font-face"), :<, css.index(":root")
  end

  test "every font face is a packaged woff2 file with its licence" do
    css = OpenBlog::BuildCss.themes
    fonts = OpenBlog::Engine.root.join("app/assets/fonts/open_blog")
    files = css.scan(/url\("([^"]+)"\) format\("woff2"\)/).flatten
    assert_equal OpenBlog::Themes::FONTS.map(&:file), files
    assert_equal files.sort, Dir[fonts.join("*.woff2")].map { |path| File.basename(path) }.sort
    files.each { |file| assert_equal "wOF2", File.binread(fonts.join(file), 4), file }
    assert_equal OpenBlog::Themes::FONTS.length, css.scan("font-display: swap;").length
    assert_equal OpenBlog::Themes::FONTS.length, css.scan(/unicode-range: U\+/).length
    OpenBlog::Themes::FONTS.map { |font| font.family.downcase.tr(" ", "-") }.uniq.each do |family|
      assert_includes fonts.join("OFL-#{family}.txt").read, "SIL OPEN FONT LICENSE Version 1.1"
    end
    stacks = OpenBlog::Themes.names.flat_map { |name| OpenBlog::Themes.fetch(name).tokens.values_at("font-display", "font-body", "font-mono") }
    stacks.each do |stack|
      assert_includes OpenBlog::Themes::FONTS.map(&:family), stack[/\A"([^"]+)"/, 1]
      assert_match(/, (?:sans-serif|serif|monospace)\z/, stack)
    end
  end

  test "copied theme sources carry no token values and use only known tokens" do
    known = (OpenBlog::Themes::COLOR_TOKENS + OpenBlog::Themes::TOKENS).map { |token| "--ob-#{token}" }
    theme = theme_source("theme.css").read
    refute_match(/^\s*--ob-[\w-]+\s*:/, theme)
    refute_includes theme, "open-blog:tokens"
    OpenBlog::Themes::COLOR_TOKENS.each { |token| assert_includes theme, "--color-ob-#{token}: var(--ob-#{token});" }
    blog = theme_source("blog.css").read
    refute_match(/^\s*--ob-[\w-]+\s*:/, blog)
    refute_match(/#\h{3,8}\b|rgba?\(|hsla?\(/, blog)
    assert_empty blog.scan(/var\((--ob-[\w-]+)/).flatten.uniq - known
    (OpenBlog::Themes::TOKENS - %w[font-display font-body font-mono radius-card radius-media radius-pill prose-size prose-leading content-width page-width]).each do |token|
      assert_match(/var\(--ob-#{token}, [^)]+\)/, blog, "#{token} needs a fallback for hosts that supply their own tokens")
    end
  end

  test "preset flourishes and both question markups are styled" do
    blog = theme_source("blog.css").read
    assert_includes blog, ':root[data-ob-theme="editorial"] .ob-prose > p:first-of-type::first-letter'
    assert_includes blog, ':root[data-ob-theme="ink"] .ob-prose h2::before'
    assert_includes blog, "counter(ob-section, decimal-leading-zero)"
    assert_match(/:is\(\[data-ob-theme="editorial"\], \[data-ob-theme="ink"\]\) :is\([^)]*\.ob-figure img[^)]*\) \{ border: var\(--ob-rule-width\)/, blog)
    assert_match(/data-ob-theme="ink"\] :is\([^)]*\.ob-figure img[^)]*\) \{ border-color: var\(--ob-border-strong\)/, blog)
    assert_match(/data-ob-theme="ink"\] \.ob-list-main \.ob-post-card \{[^}]*border: var\(--ob-rule-width\) solid var\(--ob-border-strong\)/, blog)
    assert_includes blog, ".ob-faq-entry + .ob-faq-entry {"
    assert_match(/details\.ob-faq-entry > summary \{[^}]*min-height: 2\.75rem/, blog)
    assert_includes blog, "details.ob-faq-entry[open] > summary::after"
    assert_includes blog, ".ob-page summary:focus-visible"
  end

  test "every effective GitHub syntax text color meets normal code contrast in both themes" do
    generated = OpenBlog::SyntaxCss.render(theme: "github")
    packaged = theme_source("syntax.css").read
    [ generated, packaged ].each { |css| assert_syntax_contrast(css) }
  end

  test "GitHub syntax colors stay readable on the code background of every preset" do
    css = theme_source("syntax.css").read
    OpenBlog::Themes.names.each do |name|
      preset = OpenBlog::Themes.fetch(name)
      assert_syntax_contrast(css, backgrounds: { light: preset.light.fetch("code-bg"), dark: preset.dark.fetch("code-bg") })
    end
  end

  test "copied views contain no literal colors or unprefixed palette utilities" do
    Dir[OpenBlog::Engine.root.join("lib/generators/open_blog/install/templates/views/**/*")].select { |path| File.file?(path) }.each do |path|
      source = File.read(path)
      refute_match(/#[0-9a-f]{3,8}\b|rgba?\(|hsla?\(|\b(?:text|bg|border)-(?:slate|gray|red|blue|green|white|black)(?:-\d+)?\b/i, source, path)
    end
  end

  private

  def theme_source(name)
    OpenBlog::Engine.root.join("lib/generators/open_blog/install/templates/theme", name)
  end

  def assert_syntax_contrast(css, backgrounds: {})
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
        background = values.fetch("background-color", backgrounds.fetch(mode, base.fetch("background-color")))
        assert_contrast values.fetch("color", base.fetch("color")), background, "#{mode} #{selector}"
      end
    end
  end

  def declarations(source)
    source.scan(/([\w-]+)\s*:\s*([^;{}]+)\s*;/).to_h.transform_values(&:strip)
  end

  def assert_contrast(foreground, background, label)
    ratio = OpenBlog::Themes.contrast(foreground, background)
    assert_operator ratio, :>=, 4.5, "#{label}: #{foreground} on #{background} gives #{ratio.round(3)}"
  end
end

class ThemeAssetsTest < ActionDispatch::IntegrationTest
  test "the preset stylesheet and its fonts are served from the engine" do
    get ActionController::Base.helpers.asset_path("open_blog/themes.css")
    assert_response :success
    assert_equal "text/css", response.media_type
    urls = response.body.scan(/url\("([^"]+)"\)/).flatten
    assert_equal OpenBlog::Themes::FONTS.length, urls.length
    urls.each do |url|
      assert_match(%r{\A/assets/open_blog/[\w-]+-\h+\.woff2\z}, url)
      get url
      assert_response :success
      assert_equal "wOF2", response.body.byteslice(0, 4)
    end
  end
end
