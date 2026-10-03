require "rails/engine"
require "action_dispatch"

module OpenBlog
  class Engine < ::Rails::Engine
    isolate_namespace OpenBlog
    engine_name "open_blog"

    initializer "open_blog.assets", before: "propshaft.assets_middleware" do |application|
      if application.config.respond_to?(:assets)
        application.config.assets.paths << root.join("app/assets")
      end
    end

    initializer "open_blog.markdown_mime" do
      Mime::Type.register "text/markdown", :md unless Mime[:md]
    end

    config.after_initialize do |application|
      if Engine.first_install?(application)
        OpenBlog.config.validate_structure!
      else
        OpenBlog.config.validate!
      end
    end

    def self.first_install?(application)
      defined?(Rails::Command::GenerateCommand) &&
        ARGV.first == "open_blog:install" &&
        !application.root.join("config/initializers/open_blog.rb").exist?
    end
  end
end
