require "minitest/autorun"
require "fileutils"
require "open3"
require "tmpdir"

class EngineBootTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  IDENTITY = <<~RUBY.freeze
    OpenBlog.configure do |config|
      config.site_name = "Example"
      config.default_author = { name: "Ada Example", type: :person }
      config.publisher = { name: "Example Ltd", url: "https://example.test" }
    end
  RUBY

  def test_configured_host_boots_after_its_initializer
    with_host do |directory|
      output, status = rails(directory, "runner", "puts OpenBlog.mount_path; puts Mime[:md]")
      assert status.success?, output
      assert_includes output, "/journal\ntext/markdown"
    end
  end

  def test_missing_author_refuses_boot
    with_host(identity: IDENTITY.lines.reject { |line| line.include?("default_author") }.join) do |directory|
      output, status = rails(directory, "runner", "puts :booted")
      refute status.success?, output
      assert_includes output, "OpenBlog::ConfigurationError"
      assert_includes output, "default_author"
      refute_match(/^booted$/, output)
    end
  end

  def test_custom_parent_renders_host_and_engine_helpers
    with_host(setup: 'require "active_record"') do |directory|
      FileUtils.mkdir_p(File.join(directory, "app/controllers"))
      FileUtils.mkdir_p(File.join(directory, "app/helpers"))
      File.write(File.join(directory, "app/controllers/reader_parent_controller.rb"), <<~RUBY)
        class ReaderParentController < ActionController::Base
          self.include_all_helpers = false
        end
      RUBY
      File.write(File.join(directory, "app/helpers/host_brand_helper.rb"), <<~RUBY)
        module HostBrandHelper
          def host_brand_name
            "Garden journal"
          end
        end
      RUBY
      File.write(File.join(directory, "app/controllers/helper_probe_controller.rb"), <<~RUBY)
        class HelperProbeController < OpenBlog::ApplicationController
          def show
            render inline: '<p><%= host_brand_name %> / <%= open_blog_lang %></p>', layout: false
          end
        end
      RUBY
      File.open(File.join(directory, "config/initializers/open_blog.rb"), "a") do |file|
        file.puts 'OpenBlog.config.parent_controller = "ReaderParentController"'
      end
      File.write(File.join(directory, "config/routes.rb"), <<~RUBY)
        Rails.application.routes.draw do
          get "/helper-probe", to: "helper_probe#show"
          mount OpenBlog::Engine => "/journal"
        end
      RUBY
      output, status = rails(directory, "runner", <<~RUBY)
        session = ActionDispatch::Integration::Session.new(Rails.application)
        session.get "/helper-probe"
        abort "Response: \#{session.response.status} \#{session.response.body}" unless session.response.status == 200
        puts session.response.body
        puts OpenBlog::ApplicationController.superclass.name
      RUBY
      assert status.success?, output
      assert_includes output, "Garden journal / en"
      assert_includes output, "ReaderParentController"
    end
  end

  def test_production_requires_public_url
    with_host do |directory|
      output, status = rails(directory, "runner", "puts :booted", environment: "production")
      refute status.success?, output
      assert_includes output, "public_base_url"
      File.open(File.join(directory, "config/initializers/open_blog.rb"), "a") do |file|
        file.puts 'OpenBlog.config.public_base_url = "https://example.test"'
      end
      output, status = rails(directory, "runner", "puts :booted", environment: "production")
      assert status.success?, output
      assert_match(/^booted$/, output)
    end
  end

  def test_first_install_generator_can_boot_without_identity
    with_host(identity: nil) do |directory|
      output, status = rails(directory, "generate", "open_blog:install")
      assert status.success?, output
      assert File.exist?(File.join(directory, "generator-reached")), output
    end
  end

  def test_first_install_alias_can_boot_without_identity
    with_host(identity: nil) do |directory|
      output, status = rails(directory, "g", "open_blog:install")
      assert status.success?, output
      assert File.exist?(File.join(directory, "generator-reached")), output
    end
  end

  def test_unconfigured_normal_commands_cannot_use_install_exception
    with_host(identity: nil) do |directory|
      [ [ "runner", "puts :booted" ], [ "generate", "model", "BootstrapProbe" ],
        [ "destroy", "open_blog:install" ], [ "generate", "open_blog:install_extra" ] ].each do |arguments|
        output, status = rails(directory, *arguments)
        refute status.success?, "#{arguments}: #{output}"
        assert_includes output, "OpenBlog::ConfigurationError"
      end
      refute File.exist?(File.join(directory, "generator-reached"))
    end
  end

  def test_existing_invalid_initializer_cannot_use_install_exception
    with_host(identity: "OpenBlog.config.site_name = 'Example'\n") do |directory|
      output, status = rails(directory, "generate", "open_blog:install")
      refute status.success?, output
      assert_includes output, "default_author"
      refute File.exist?(File.join(directory, "generator-reached"))
    end
  end

  def test_first_install_still_validates_body_formats
    with_host(identity: nil, setup: "OpenBlog.config.body_formats = [:unknown]") do |directory|
      output, status = rails(directory, "generate", "open_blog:install")
      refute status.success?, output
      assert_includes output, "body_formats"
      refute File.exist?(File.join(directory, "generator-reached"))
    end
  end

  private

  def rails(directory, *arguments, environment: "development")
    Open3.capture2e({ "BUNDLE_GEMFILE" => ENV.fetch("BUNDLE_GEMFILE", File.join(ROOT, "Gemfile")), "RAILS_ENV" => environment },
      Gem.ruby, "-I#{File.join(ROOT, 'lib')}", "bin/rails", *arguments, chdir: directory)
  end

  def with_host(identity: IDENTITY, setup: "")
    Dir.mktmpdir("open-blog-host") do |directory|
      %w[bin config/initializers lib/generators/open_blog/install].each do |path|
        FileUtils.mkdir_p(File.join(directory, path))
      end
      File.write(File.join(directory, "bin/rails"), <<~RUBY)
        APP_PATH = File.expand_path("../config/application", __dir__)
        require "bundler/setup"
        require "rails/commands"
      RUBY
      File.write(File.join(directory, "config/application.rb"), <<~RUBY)
        require "rails"
        require "action_controller/railtie"
        require "open_blog"
        #{setup}
        module ExampleHost
          class Application < Rails::Application
            config.root = File.expand_path("..", __dir__)
            config.load_defaults 8.0
            config.eager_load = false
            config.secret_key_base = "test-secret-" * 8
            config.logger = Logger.new(File::NULL)
            config.hosts.clear
          end
        end
      RUBY
      File.write(File.join(directory, "config/environment.rb"), <<~RUBY)
        require_relative "application"
        Rails.application.initialize!
      RUBY
      File.write(File.join(directory, "config/routes.rb"), <<~RUBY)
        Rails.application.routes.draw { mount OpenBlog::Engine => "/journal" }
      RUBY
      if identity
        File.write(File.join(directory, "config/initializers/open_blog.rb"), identity)
      end
      File.write(File.join(directory, "lib/generators/open_blog/install/install_generator.rb"), <<~RUBY)
        module OpenBlog
          class InstallGenerator < Rails::Generators::Base
            def mark_invocation
              File.write(Rails.root.join("generator-reached"), "yes")
            end
          end
        end
      RUBY
      yield directory
    end
  end
end
