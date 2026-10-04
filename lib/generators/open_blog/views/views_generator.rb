require "rails/generators"
require_relative "../generator_support"

module OpenBlog
  module Generators
    class ViewsGenerator < Rails::Generators::Base
      include GeneratorSupport
      source_root File.expand_path("../install/templates", __dir__)
      class_option :skip_tailwind, type: :boolean, default: nil

      def copy_views
        css = if options[:skip_tailwind].nil? && host_read("app/views/layouts/open_blog.html.erb").match?(/\bopen_blog_stylesheets\b/)
          :fallback
        else
          css_setup
        end
        copy_reader_views(css: css)
      end
    end
  end
end
