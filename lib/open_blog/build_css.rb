require "fileutils"
require "open3"
require "pathname"
require "tmpdir"
require "tailwindcss/ruby"

module OpenBlog
  class BuildCss
    COMPILER_VERSION = "4.3.3"

    def self.render
      unless Gem.loaded_specs.fetch("tailwindcss-ruby").version.to_s == COMPILER_VERSION
        raise ConfigurationError, "Build stylesheets with tailwindcss-ruby #{COMPILER_VERSION}"
      end
      Dir.mktmpdir("open-blog-css") do |directory|
        input = Pathname(directory).join("input.css")
        output = Pathname(directory).join("output.css")
        input.write(<<~CSS)
          @import "tailwindcss" source(none);
          @import #{theme_root.join("theme.css").to_s.to_json};
          @source #{Engine.root.join("lib/generators/open_blog/install/templates/views").to_s.to_json};
        CSS
        _stdout, stderr, status = Open3.capture3(Tailwindcss::Ruby.executable.to_s, "--input", input.to_s,
          "--output", output.to_s, "--minify", chdir: Engine.root.to_s)
        raise ConfigurationError, "Stylesheet build failed: #{stderr.strip}" unless status.success?
        output.binread
      end
    end

    OVERRIDE = <<~CSS
      /*
        Open Blog loads this file after the preset chosen with config.theme.
        Put your token overrides here. Colours can also be set with config.theme_colors.

        :root[data-ob-theme] {
          --ob-accent: #1d4ed8;
          --ob-font-display: Georgia, serif;
          --ob-radius-card: 0.5rem;
        }
        :root[data-ob-theme][data-theme="dark"] {
          --ob-accent: #93c5fd;
        }
        @media (prefers-color-scheme: dark) {
          :root[data-ob-theme]:not([data-theme="light"]) {
            --ob-accent: #93c5fd;
          }
        }
      */
    CSS

    COLOR_SCHEME = <<~CSS
      :root { color-scheme: light dark; }
      :root[data-theme="light"] { color-scheme: light; }
      :root[data-theme="dark"] { color-scheme: dark; }
    CSS

    def self.tokens
      OVERRIDE
    end

    def self.themes
      faces = Themes::FONTS.map do |font|
        <<~CSS
          @font-face {
            font-family: "#{font.family}";
            font-style: #{font.style};
            font-weight: #{font.weight};
            font-display: swap;
            src: url("#{font.file}") format("woff2");
            unicode-range: #{font.range};
          }
        CSS
      end
      presets = Themes.names.map do |name|
        preset = Themes.fetch(name)
        Themes.css(name, light: preset.light.merge(preset.tokens), dark: preset.dark)
      end
      [ *faces, COLOR_SCHEME, *presets ].join
    end

    def self.write(path: Engine.root.join("app/assets/builds/open_blog/blog.css"), tokens_path: theme_root.join("open_blog_theme.css"),
      themes_path: Pathname(path).dirname.join("themes.css"))
      [ [ path, render ], [ tokens_path, tokens ], [ themes_path, themes ] ].each do |destination, bytes|
        destination = Pathname(destination)
        FileUtils.mkdir_p(destination.dirname)
        destination.binwrite(bytes)
      end
      Pathname(path)
    end

    def self.theme_root
      Engine.root.join("lib/generators/open_blog/install/templates/theme")
    end
    private_class_method :theme_root
  end
end
