require "rails/generators"
require "bundler"
require_relative "../generator_support"

module OpenBlog
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include GeneratorSupport
      source_root File.expand_path("templates", __dir__)
      source_paths << OpenBlog::Engine.root.join("app/assets/javascripts").to_s

      class_option :skip_tailwind, type: :boolean, default: false
      class_option :body_format, type: :string, default: "markdown"
      class_option :mount_at, type: :string, default: "/blog"
      class_option :mount_position, type: :string, default: "last"
      class_option :site_name, type: :string
      class_option :author_name, type: :string
      class_option :skip_sample, type: :boolean, default: false
      class_option :skip_migrate, type: :boolean, default: false
      class_option :admin_suite, type: :boolean, default: false

      def detect
        unless %w[markdown rich_text both].include?(options[:body_format])
          raise Thor::Error, "--body-format must be markdown, rich_text or both"
        end
        unless %w[first last].include?(options[:mount_position])
          raise Thor::Error, "--mount-position must be first or last"
        end
        unless options[:mount_at].match?(%r{\A/(?:[a-zA-Z0-9_-]+(?:/[a-zA-Z0-9_-]+)*)?\z})
          raise Thor::Error, "--mount-at must be an absolute path without a query, fragment or trailing slash"
        end
        @javascript = javascript_setup
        @css = css_setup
        @install_stimulus = !File.file?(host_file("app/javascript/controllers/index.js"))
        @install_tailwind = @css == :none
        say "JavaScript: #{@javascript}; stylesheets: #{@css}"
        say "Tailwind 3 detected; using the built blog stylesheet." if @css == :legacy
        if @install_tailwind
          say "Tailwind's installer changes the host layout, bin/dev and Procfile.dev. Use --skip-tailwind to keep your existing CSS setup."
        end
        say "The JavaScript installers may update the host entrypoint and controller manifest." if @install_stimulus || @javascript != :importmap
      end

      def configure_blog
        @site_name = identity(:site_name, "Site name", "Example")
        @author_name = identity(:author_name, "Author name", "Ada Example")
        template "initializer.rb.tt", "config/initializers/open_blog.rb", **copy_options
      end

      def install_dependencies
        processor = (Rails.application.config.active_storage.variant_processor || :vips).to_sym
        backend = { vips: "ruby-vips", mini_magick: "mini_magick" }.fetch(processor) do
          raise Thor::Error, "Unsupported Active Storage variant processor: #{processor}"
        end
        additions = [ "stimulus-rails", "image_processing", backend ]
        additions << "importmap-rails" if @javascript == :none
        additions << "tailwindcss-rails" if @install_tailwind
        added = additions.reject { |name| host_read("Gemfile").match?(/^\s*gem\s+["']#{Regexp.escape(name)}["']/) }
        added.each { |name| gem(name, *(name == "tailwindcss-rails" ? [ "~> 4.0" ] : [])) }
        run_host_command("bundle", "install") if added.any?
        if @javascript == :none
          run_host_command("bin/rails", "importmap:install")
          @javascript = :importmap
        end
        run_host_command("bin/rails", "stimulus:install") if @install_stimulus
        if @install_tailwind
          run_host_command("bin/rails", "tailwindcss:install")
          @css = :rails
        end
      end

      def install_migrations
        run_host_command("bin/rails", "railties:install:migrations", "FROM=active_storage,action_text,open_blog")
        run_host_command("bin/rails", "db:migrate") unless options[:skip_migrate]
      end

      def mount_engine
        return if host_read("config/routes.rb").match?(/^\s*mount\s+OpenBlog::Engine\b/)
        declaration = "  mount OpenBlog::Engine, at: #{options[:mount_at].dump}\n"
        if options[:mount_position] == "first"
          unless host_read("config/routes.rb").match?(/Rails\.application\.routes\.draw do\s*\n/)
            raise Thor::Error, "Cannot locate the routes draw block; mount OpenBlog::Engine manually."
          end
          inject_into_file "config/routes.rb", declaration, after: /Rails\.application\.routes\.draw do\s*\n/
        else
          unless host_read("config/routes.rb").match?(/^end\s*\z/)
            raise Thor::Error, "Cannot locate the routes draw block; mount OpenBlog::Engine manually."
          end
          inject_into_file "config/routes.rb", declaration, before: /^end\s*\z/
        end
      end

      def install_views
        copy_reader_views(css: @css, javascript: @javascript)
      end

      def install_theme
        if %i[rails bundler].include?(@css)
          %w[theme.css blog.css syntax.css].each do |name|
            copy_file "theme/#{name}", "app/assets/tailwind/open_blog/#{name}", **copy_options
          end
          entry, import = if @css == :rails
            [ "app/assets/tailwind/application.css", '@import "./open_blog/theme.css";' ]
          else
            [ "app/assets/stylesheets/application.tailwind.css", '@import "../tailwind/open_blog/theme.css";' ]
          end
          append_once(entry, "\n#{import}\n")
        else
          copy_file "theme/open_blog_theme.css", "app/assets/stylesheets/open_blog_theme.css", **copy_options
        end
      end

      def install_controllers
        directory "open_blog/controllers", "app/javascript/controllers/open_blog", **copy_options
        if @javascript == :bundler
          say "Regenerating the host Stimulus controller manifest."
          run_host_command("bin/rails", "stimulus:manifest:update")
        else
          append_once "config/importmap.rb", "\npin_all_from \"app/javascript/controllers\", under: \"controllers\"\n"
          index = "app/javascript/controllers/index.js"
          unless host_read(index).match?(/(?:eager|lazy)LoadControllersFrom\s*\(/)
            controller_names.each do |name|
              identifier = "open-blog--#{name.tr('_', '-')}"
              next if host_read(index).match?(/application\.register\(\s*["']#{Regexp.escape(identifier)}["']/)
              variable = "OpenBlog#{name.camelize}Controller"
              append_to_file index, "\nimport #{variable} from \"controllers/open_blog/#{name}_controller\"\napplication.register(#{identifier.dump}, #{variable})\n"
            end
          end
        end
        say "Blog JavaScript entrypoint: application. Register these controllers there if you use another public entrypoint."
      end

      def install_text
        copy_file OpenBlog::Engine.root.join("config/locales/open_blog.en.yml").to_s, "config/locales/open_blog.en.yml", **copy_options
      end

      def sample_and_report
        if options[:skip_migrate]
          say "Sample deferred: run db:migrate, then open_blog:sample when ready."
        elsif !options[:skip_sample]
          run_host_command("bin/rails", "open_blog:sample")
        end
        say "Blog: #{options[:mount_at]}"
        if options[:skip_migrate]
          say "API token deferred: run db:migrate, then open_blog:install_token."
        else
          run_host_command("bin/rails", "open_blog:install_token")
        end
        say "Publishing API: #{options[:mount_at].chomp('/')}/api/v1"
        say "The MCP endpoint will be available in a later release."
        say "AdminSuite generator is not available in this release." if options[:admin_suite]
        say "Next: set your public base URL, review publisher details and policy links, and customize the theme."
        run_host_command("bin/rails", "open_blog:doctor")
      end

      private

      def run_host_command(*arguments)
        say_status :run, arguments.join(" ")
        return true if options[:pretend]
        success = Bundler.with_unbundled_env { system(*arguments, chdir: destination_root) }
        if !success && arguments == [ "bin/rails", "open_blog:doctor" ]
          say "Doctor found setup issues; review the report above and run open_blog:doctor after completing setup."
        elsif !success
          raise Thor::Error, "Host command failed: #{arguments.join(' ')}"
        end
        success
      end

      def identity(key, prompt, placeholder)
        return options[key] if options[key].present?
        return ask("#{prompt}:", default: placeholder) if $stdin.tty?
        say "Using placeholder #{prompt.downcase} #{placeholder.inspect}; update config/initializers/open_blog.rb."
        placeholder
      end

      def controller_names
        Dir[OpenBlog::Engine.root.join("app/assets/javascripts/open_blog/controllers/*_controller.js")].map do |path|
          File.basename(path, "_controller.js")
        end.sort
      end

      def body_formats
        options[:body_format] == "both" ? %i[markdown rich_text] : [ options[:body_format].to_sym ]
      end
    end
  end
end
