module OpenBlog
  module ThemeHelper
    SURFACES = { "light" => "#ffffff", "dark" => "#0f172a" }.freeze

    def open_blog_fixed_theme
      OpenBlog.config.color_scheme.to_s if %w[light dark].include?(OpenBlog.config.color_scheme.to_s)
    end

    def open_blog_theme_attributes
      data = { theme: open_blog_fixed_theme, ob_theme: open_blog_preset&.name&.to_s }.compact
      data.any? ? { data: data } : {}
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
      preset = open_blog_preset
      surfaces = SURFACES.to_h do |scheme, surface|
        [ scheme, preset ? preset.public_send(scheme).merge(OpenBlog.config.theme_colors_for(scheme.to_sym)).fetch("surface") : surface ]
      end
      safe_join(surfaces.map do |scheme, surface|
        tag.meta(name: "theme-color", media: "(prefers-color-scheme: #{scheme})", content: surfaces.fetch(open_blog_fixed_theme, surface))
      end, "\n")
    end

    def open_blog_stylesheets
      stylesheets = [ open_blog_preset_stylesheet, stylesheet_link_tag("open_blog/blog") ]
      stylesheets << stylesheet_link_tag("open_blog_theme") if open_blog_theme_override?
      safe_join([ *stylesheets, open_blog_theme_color_overrides ].compact, "\n")
    end

    def open_blog_theme_stylesheets
      safe_join([ open_blog_preset_stylesheet, open_blog_theme_color_overrides ].compact, "\n")
    end

    private

    def open_blog_preset
      Themes.fetch(OpenBlog.config.theme) unless OpenBlog.config.theme == :none
    end

    def open_blog_preset_stylesheet
      stylesheet_link_tag("open_blog/themes") if open_blog_preset
    end

    def open_blog_theme_color_overrides
      return unless open_blog_preset
      colors = Configuration::THEME_MODES.index_with { |mode| OpenBlog.config.theme_colors_for(mode) }
      css = Themes.css(open_blog_preset.name, **colors)
      tag.style(css.html_safe, nonce: content_security_policy_nonce, data: { open_blog_theme_colors: true }) if css.present?
    end

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
