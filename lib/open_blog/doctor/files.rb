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
        colors = Configuration::THEME_MODES.index_with { |mode| @config.theme_colors_for(mode) }
        preset = Themes.fetch(@config.theme) unless @config.theme == :none
        problem = theme_files(preset)
        return [ "error", problem ] if problem
        warnings = []
        warnings << "theme_colors has no effect with theme :none." if preset.nil? && colors.values.any?(&:any?)
        low = preset ? low_contrast(preset, colors) : []
        warnings << "Theme colours below #{Themes::MIN_CONTRAST}:1 contrast: #{low.join(', ')}." if low.any?
        stale = stale_component_styles(preset)
        warnings << stale if stale
        if Dir[@root.join("app/views/layouts/**/*")].select { |path| File.file?(path) }.any? { |path| File.read(path).match?(/stylesheet_link_tag\s*(?:\(?\s*):all\b/) }
          warnings << "Replace stylesheet_link_tag :all to avoid loading the blog reset on other pages."
        end
        return [ "warning", warnings.join(" ") ] if warnings.any?
        [ "ok", "Theme #{@config.theme}: sources and compiled stylesheets are available." ]
      rescue ConfigurationError => error
        [ "error", error.message ]
      end

      def low_contrast(preset, colors)
        colors.flat_map do |mode, overrides|
          Themes.low_contrast(preset.public_send(mode).merge(overrides)).map do |foreground, background, ratio|
            "#{mode} #{foreground.tr('-', '_')} on #{background.tr('-', '_')} #{ratio.floor(2)}:1"
          end
        end
      end

      def stale_component_styles(preset)
        return if layout_source.include?("open_blog_stylesheets")
        path = "app/assets/tailwind/open_blog/blog.css"
        source = read(path)
        absent = []
        absent << "preset" if preset && !source.include?("data-ob-theme")
        absent << "collapsed FAQ" if @config.faq_collapsed && !source.include?("details.ob-faq-entry")
        return if absent.empty?
        "#{path} has no #{absent.join(' or ')} rules. Delete it#{' and theme.css in the same directory' if preset}, then run bin/rails generate open_blog:install."
      end

      def theme_files(preset)
        layout = layout_source
        tailwind = @root.join("app/assets/tailwind/application.css")
        bundled = @root.join("app/assets/stylesheets/application.tailwind.css")
        if !layout.include?("open_blog_stylesheets")
          asset = layout[/stylesheet_link_tag\s*\(?\s*["']([^"']+)["']/, 1]
          return "The blog layout must load the installed stylesheet." unless %w[tailwind application].include?(asset)
          return "The blog layout must call open_blog_theme_stylesheets to load the #{preset.name} theme." if preset && !layout.include?("open_blog_theme_stylesheets")
          entry = asset == "tailwind" ? tailwind : bundled
          return "Missing Tailwind entry stylesheet #{entry.relative_path_from(@root)}." unless entry.file?
          source = entry.read
          return "Import open_blog/theme.css in #{entry.relative_path_from(@root)}." unless source.match?(/@import\s+["'][^"']*open_blog\/theme(?:\.css)?["']/)
          absent = %w[theme blog syntax].reject { |name| @root.join("app/assets/tailwind/open_blog/#{name}.css").file? }
          return "Missing theme sources: #{absent.join(', ')}." if absent.any?
          assets = [ "#{asset}.css" ]
        else
          return "Install app/assets/stylesheets/open_blog_theme.css." unless @root.join("app/assets/stylesheets/open_blog_theme.css").file?
          assets = [ "open_blog/blog.css" ]
        end
        assets << "open_blog/themes.css" if preset
        missing = assets.reject { |asset| @application.assets&.resolver&.resolve(asset) }
        "Build the missing #{missing.join(', ')} stylesheet." if missing.any?
      end
    end
  end
end
