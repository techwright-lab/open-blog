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

    def self.tokens
      source = theme_root.join("theme.css").read
      block = source.match(%r{/\* open-blog:tokens:start \*/(.*?)/\* open-blog:tokens:end \*/}m)
      raise ConfigurationError, "The theme must contain its marked token block" unless block
      "#{block[1].strip}\n"
    end

    def self.write(path: Engine.root.join("app/assets/builds/open_blog/blog.css"), tokens_path: theme_root.join("open_blog_theme.css"))
      css = render
      values = tokens
      [ [ path, css ], [ tokens_path, values ] ].each do |destination, bytes|
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
