require "rails/generators"
require "pathname"
require_relative "../generator_support"

module OpenBlog
  module Generators
    class AdminSuiteGenerator < Rails::Generators::Base
      include GeneratorSupport
      source_root File.expand_path("templates", __dir__)
      class_option :dir, type: :string, default: "app/admin", desc: "Host directory for admin definitions"

      def copy_definitions
        path = Pathname.new(options[:dir])
        if path.absolute? || path.each_filename.include?("..") || options[:dir].match?(/[\x00-\x1f*?\[\]{}]/)
          raise Thor::Error, "Choose a relative host directory without traversal or glob characters."
        end
        @admin_dir = path.cleanpath.to_s
        %w[post category author page].each do |name|
          template "#{name}_resource.rb.tt", "#{@admin_dir}/resources/open_blog/#{name}_resource.rb", **copy_options
        end
        template "blog_portal.rb.tt", "#{@admin_dir}/portals/open_blog_portal.rb", **copy_options
        template "initializer.rb.tt", "config/initializers/open_blog_admin_suite.rb", **copy_options
        say "Admin definitions written. Install AdminSuite 0.6.1 or later to activate them; restart the host after adding definitions."
      end
    end
  end
end
