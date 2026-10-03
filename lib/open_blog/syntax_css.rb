require "rouge"
require "fileutils"
require "pathname"

module OpenBlog
  class SyntaxCss
    LIGHT_SCOPE = ".ob-highlight"
    DARK_SCOPE = '[data-theme="dark"] .ob-highlight'
    SYSTEM_SCOPE = 'html:not([data-theme="light"]) .ob-highlight'

    def self.render(theme: OpenBlog.config.syntax_theme)
      selected = Rouge::Theme.find(theme)
      unless selected && selected.respond_to?(:mode) && selected.respond_to?(:make_light!) && selected.respond_to?(:make_dark!)
        raise ConfigurationError, "Syntax theme #{theme.inspect} must provide light and dark modes; try github, base16, or gruvbox."
      end
      light = selected.mode(:light).render(scope: LIGHT_SCOPE)
      dark = selected.mode(:dark).render(scope: DARK_SCOPE)
      system = selected.mode(:dark).render(scope: SYSTEM_SCOPE)
      css = "#{light}\n\n#{dark}\n\n@media (prefers-color-scheme: dark) {\n#{system}\n}\n"
      css += github_contrast if selected == Rouge::Themes::Github
      css
    end

    def self.github_contrast
      comments = %w[c ch cd cm cp cpf c1 cs gl gt].map { |name| "#{LIGHT_SCOPE} .#{name}" }.join(", ")
      <<~CSS
        #{LIGHT_SCOPE} .gr { color: #cf222e; }
        #{comments} { color: #57606a; }
        #{DARK_SCOPE} .gh, #{DARK_SCOPE} .gu { color: #79c0ff; }
        @media (prefers-color-scheme: dark) {
          #{SYSTEM_SCOPE} .gh, #{SYSTEM_SCOPE} .gu { color: #79c0ff; }
        }
      CSS
    end
    private_class_method :github_contrast

    def self.write(root: Rails.root, path: nil, theme: OpenBlog.config.syntax_theme)
      root = Pathname(root)
      destination = path ? root.join(path) : default_path(root)
      css = render(theme: theme)
      FileUtils.mkdir_p(destination.dirname)
      destination.write(css)
      destination
    end

    def self.default_path(root)
      tailwind = root.join("app/assets/tailwind/open_blog/syntax.css")
      stylesheets = root.join("app/assets/stylesheets/open_blog/syntax.css")
      return tailwind if tailwind.file?
      return stylesheets if stylesheets.file?
      root.join("app/assets/tailwind/application.css").file? ? tailwind : stylesheets
    end
    private_class_method :default_path
  end
end
