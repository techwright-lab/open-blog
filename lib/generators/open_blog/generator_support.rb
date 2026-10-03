require "json"

module OpenBlog
  module Generators
    module GeneratorSupport
      private

      def host_file(path)
        File.join(destination_root, path)
      end

      def host_read(path)
        File.file?(host_file(path)) ? File.read(host_file(path)) : ""
      end

      def javascript_setup
        return :importmap if File.file?(host_file("config/importmap.rb"))
        return :bundler if File.file?(host_file("package.json"))
        :none
      end

      def css_setup
        return :fallback if options[:skip_tailwind]
        package = JSON.parse(host_read("package.json").presence || "{}")
        version = package.fetch("dependencies", {}).merge(package.fetch("devDependencies", {}))["tailwindcss"].to_s
        gemfile = host_read("Gemfile")
        old_gem = gemfile.match?(/^\s*gem\s+["']tailwindcss-rails["']\s*,\s*["'][~>\s]*3(?:\.|["'])/)
        old_gem ||= host_read("Gemfile.lock").match?(/^    tailwindcss-rails \(3\./)
        old_gem ||= host_read("app/assets/stylesheets/application.tailwind.css").match?(/@tailwind\s+(?:base|components|utilities)\b/)
        return :legacy if version.match?(/\A[~^>=\s]*3(?:\.|\z)/) || old_gem
        return :rails if File.file?(host_file("app/assets/tailwind/application.css"))
        if version.match?(/\A[~^>=\s]*4(?:\.|\z)/) && File.file?(host_file("app/assets/stylesheets/application.tailwind.css"))
          return :bundler
        end
        :none
      rescue JSON::ParserError => error
        raise Thor::Error, "Cannot read package.json: #{error.message}"
      end

      def copy_options
        { force: options[:force], skip: options[:skip] || (!options[:force] && !$stdin.tty?) }
      end

      def copy_reader_views(css: css_setup, javascript: javascript_setup)
        directory "views/open_blog", "app/views/open_blog", **copy_options
        content = File.read(find_in_source_paths("views/layouts/open_blog.html.erb"))
        stylesheet = case css
        when :rails then 'stylesheet_link_tag "tailwind", "data-turbo-track": "reload"'
        when :bundler then 'stylesheet_link_tag "application", "data-turbo-track": "reload"'
        else "open_blog_stylesheets"
        end
        content = content.sub("open_blog_stylesheets", stylesheet)
        if javascript == :bundler
          content = content.sub("javascript_importmap_tags", 'javascript_include_tag "application", "data-turbo-track": "reload", defer: true')
        end
        create_file "app/views/layouts/open_blog.html.erb", content, **copy_options
      end

      def append_once(path, content)
        append_to_file(path, content) unless host_read(path).include?(content.strip)
      end
    end
  end
end
