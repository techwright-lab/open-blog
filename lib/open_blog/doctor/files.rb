module OpenBlog
  class Doctor
    module Files
      private

      def read(path)
        file = @root.join(path)
        file.file? ? file.read : ""
      end

      def layout_source
        read("app/views/layouts/#{@config.layout}.html.erb")
      end

      def views
        layout = layout_source
        content = view_tree("app/views/open_blog/posts/show.html.erb")
        required = %w[open_blog_post_content open_blog_notices open_blog_byline open_blog_faq open_blog_responsible_party_link open_blog_cover]
        absent = required.reject { |helper| content.match?(/\b#{helper}\b/) }
        absent += %w[open_blog_head open_blog_structured_data].reject { |helper| layout.match?(/\b#{helper}\b/) }
        absent << "original content cover (variant found)" if content.match?(/cover_image[^\n]*\.variant\b/)
        absent.any? ? [ "error", "Copied views are missing required helpers: #{absent.join(', ')}." ] : [ "ok", "Copied layout and post partials call the reader helpers." ]
      end

      def view_tree(path, seen = [])
        return "" if seen.include?(path)
        seen << path
        source = read(path)
        partials = source.scan(/\brender\s*(?:\(?\s*)(?:partial:\s*)?["']([^"']+)["']/).flatten
        source + partials.map do |partial|
          directory, name = File.dirname(partial), File.basename(partial)
          view_tree("app/views/#{directory}/_#{name}.html.erb", seen)
        end.join("\n")
      end

      def theme
        layout = layout_source
        tailwind = @root.join("app/assets/tailwind/application.css")
        bundled = @root.join("app/assets/stylesheets/application.tailwind.css")
        if !layout.include?("open_blog_stylesheets")
          asset = layout[/stylesheet_link_tag\s*\(?\s*["']([^"']+)["']/, 1]
          return [ "error", "The blog layout must load the installed stylesheet." ] unless %w[tailwind application].include?(asset)
          entry = asset == "tailwind" ? tailwind : bundled
          return [ "error", "Missing Tailwind entry stylesheet #{entry.relative_path_from(@root)}." ] unless entry.file?
          source = entry.read
          return [ "error", "Import open_blog/theme.css in #{entry.relative_path_from(@root)}." ] unless source.match?(/@import\s+["'][^"']*open_blog\/theme(?:\.css)?["']/)
          absent = %w[theme blog syntax].reject { |name| @root.join("app/assets/tailwind/open_blog/#{name}.css").file? }
          return [ "error", "Missing theme sources: #{absent.join(', ')}." ] if absent.any?
          asset = "#{asset}.css"
        else
          return [ "error", "Install app/assets/stylesheets/open_blog_theme.css." ] unless @root.join("app/assets/stylesheets/open_blog_theme.css").file?
          asset = "open_blog/blog.css"
          return [ "error", "The blog layout must load open_blog_stylesheets." ] unless layout.include?("open_blog_stylesheets")
        end
        return [ "error", "Build the missing #{asset} stylesheet." ] unless @application.assets&.resolver&.resolve(asset)
        all = Dir[@root.join("app/views/layouts/**/*")].select { |path| File.file?(path) }.any? { |path| File.read(path).match?(/stylesheet_link_tag\s*(?:\(?\s*):all\b/) }
        all ? [ "warning", "Replace stylesheet_link_tag :all to avoid loading the blog reset on other pages." ] : [ "ok", "Theme sources and compiled stylesheet are available." ]
      end
    end
  end
end
