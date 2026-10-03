require_relative "test_helper"
require "tmpdir"
require "rake"

class SyntaxCssTest < ActiveSupport::TestCase
  test "light and both dark scopes use complete Rouge theme output" do
    css = OpenBlog::SyntaxCss.render(theme: "github")
    light = Rouge::Themes::Github.mode(:light).render(scope: ".ob-highlight")
    explicit = Rouge::Themes::Github.mode(:dark).render(scope: '[data-theme="dark"] .ob-highlight')
    system = Rouge::Themes::Github.mode(:dark).render(scope: 'html:not([data-theme="light"]) .ob-highlight')
    assert css.start_with?(light)
    assert_includes css, explicit
    assert_includes css, "@media (prefers-color-scheme: dark) {\n#{system}\n}"
    assert_scoped(css)
  end

  test "supported dual-mode themes work without changing their default mode" do
    %w[github base16 gruvbox].each do |name|
      theme = Rouge::Theme.find(name)
      original = theme.mode
      css = OpenBlog::SyntaxCss.render(theme: name)
      assert_equal original, theme.mode
      assert_includes css, theme.mode(:light).render(scope: ".ob-highlight")
      assert_includes css, theme.mode(:dark).render(scope: '[data-theme="dark"] .ob-highlight')
      assert_scoped(css)
    end
  end

  test "unknown and single-mode themes have actionable configuration errors" do
    %w[missing-theme monokai].each do |name|
      error = assert_raises(OpenBlog::ConfigurationError) { OpenBlog::SyntaxCss.render(theme: name) }
      assert_includes error.message, name
      assert_includes error.message, "light and dark"
    end
  end

  test "writes follow existing files and the host CSS layout" do
    Dir.mktmpdir do |directory|
      root = Pathname(directory)
      plain = OpenBlog::SyntaxCss.write(root: root, theme: "github")
      assert_equal root.join("app/assets/stylesheets/open_blog/syntax.css"), plain
      assert_equal OpenBlog::SyntaxCss.render(theme: "github"), plain.read
      FileUtils.mkdir_p(root.join("app/assets/tailwind"))
      root.join("app/assets/tailwind/application.css").write("")
      assert_equal plain, OpenBlog::SyntaxCss.write(root: root, theme: "base16")
      plain.delete
      tailwind = OpenBlog::SyntaxCss.write(root: root, theme: "github")
      assert_equal root.join("app/assets/tailwind/open_blog/syntax.css"), tailwind
      tailwind.delete
      root.join("app/assets/tailwind/application.css").delete
      root.join("app/assets/stylesheets/application.tailwind.css").write("")
      assert_equal plain, OpenBlog::SyntaxCss.write(root: root, theme: "github")
      override = root.join("custom/highlighting.css")
      assert_equal override, OpenBlog::SyntaxCss.write(root: root, path: "custom/highlighting.css", theme: "github")
      assert_scoped(override.read)
    end
  end

  test "the rake task writes to an explicit destination" do
    previous = Rake.application
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load File.expand_path("../lib/tasks/open_blog.rake", __dir__)
    Dir.mktmpdir do |directory|
      path = File.join(directory, "syntax.css")
      capture_io { Rake::Task["open_blog:syntax_css"].invoke(path) }
      assert_equal OpenBlog::SyntaxCss.render, File.read(path)
    end
  ensure
    Rake.application = previous
  end

  test "the installer ships only scoped syntax styles" do
    path = File.expand_path("../lib/generators/open_blog/install/templates/syntax.css", __dir__)
    assert File.file?(path)
    css = File.read(path)
    assert_includes css, "@media (prefers-color-scheme: dark)"
    assert_scoped(css)
  end

  private

  def assert_scoped(css)
    selectors = css.scan(/([^{}]+)\{/).flatten.map(&:strip).reject { |selector| selector.start_with?("@media") }
    assert selectors.any?
    unscoped = selectors.flat_map { |selector| selector.split(",") }.reject do |selector|
      selector.strip.match?(/\A(?:\.ob-highlight|\[data-theme="dark"\] \.ob-highlight|html:not\(\[data-theme="light"\]\) \.ob-highlight)(?:\s|\z)/)
    end
    assert_empty unscoped
  end
end
