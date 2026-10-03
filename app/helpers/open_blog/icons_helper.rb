module OpenBlog
  module IconsHelper
    ICONS = %w[sun moon monitor share copy check link].freeze

    def open_blog_icon(name)
      raise ArgumentError, "Unknown icon: #{name}" unless ICONS.include?(name.to_s)
      render partial: "open_blog/icons/#{name}", formats: [ :svg ]
    end
  end
end
