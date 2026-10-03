module OpenBlog
  module ThemeHelper
    SURFACES = { "light" => "#ffffff", "dark" => "#0f172a" }.freeze

    def open_blog_fixed_theme
      OpenBlog.config.color_scheme.to_s if %w[light dark].include?(OpenBlog.config.color_scheme.to_s)
    end

    def open_blog_theme_attributes
      open_blog_fixed_theme ? { data: { theme: open_blog_fixed_theme } } : {}
    end

    def open_blog_theme_script
      return "".html_safe if open_blog_fixed_theme
      javascript_tag(nonce: content_security_policy_nonce, data: { open_blog_theme: true }) do
        <<~JS.html_safe
          (() => {
            try {
              const theme = localStorage.getItem("open-blog-theme");
              if (theme === "light" || theme === "dark") document.documentElement.dataset.theme = theme;
            } catch (_) {}
          })();
        JS
      end
    end

    def open_blog_theme_colors
      safe_join(SURFACES.map do |scheme, surface|
        tag.meta(name: "theme-color", media: "(prefers-color-scheme: #{scheme})", content: SURFACES.fetch(open_blog_fixed_theme, surface))
      end, "\n")
    end

    def open_blog_stylesheets
      stylesheets = [ stylesheet_link_tag("open_blog/blog") ]
      stylesheets << stylesheet_link_tag("open_blog_theme") if open_blog_theme_override?
      safe_join(stylesheets, "\n")
    end

    private

    def open_blog_theme_override?
      assets = Rails.application.assets if Rails.application.respond_to?(:assets)
      if assets.respond_to?(:resolver)
        assets.resolver.resolve("open_blog_theme.css").present?
      elsif assets.respond_to?(:find_asset)
        assets.find_asset("open_blog_theme.css").present?
      elsif Rails.application.respond_to?(:assets_manifest)
        Rails.application.assets_manifest&.assets&.key?("open_blog_theme.css")
      end
    end
  end
end
