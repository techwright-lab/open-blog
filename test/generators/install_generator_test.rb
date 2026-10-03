require_relative "../test_helper"
require "rails/generators/test_case"
require "generators/open_blog/install/install_generator"
require "tmpdir"
require "minitest/mock"

class InstallGeneratorTest < Rails::Generators::TestCase
  class Recorder < OpenBlog::Generators::InstallGenerator
    source_root OpenBlog::Generators::InstallGenerator.source_root
    class << self
      attr_accessor :host_commands
    end
    self.host_commands = []

    private

    def run_host_command(*arguments)
      raise "Initializer must precede subprocesses" unless File.file?(File.join(destination_root, "config/initializers/open_blog.rb"))
      self.class.host_commands << arguments
      if arguments == [ "bin/rails", "importmap:install" ]
        create_file "config/importmap.rb", "pin \"application\"\n"
        create_file "app/javascript/application.js", ""
      elsif arguments == [ "bin/rails", "stimulus:install" ]
        create_file "app/javascript/controllers/index.js", 'eagerLoadControllersFrom("controllers", application)'
      elsif arguments == [ "bin/rails", "tailwindcss:install" ]
        create_file "app/assets/tailwind/application.css", "@import \"tailwindcss\";\n"
      end
      true
    end
  end

  tests Recorder

  setup do
    self.destination_root = Dir.mktmpdir("open-blog-generator")
    Recorder.host_commands = []
    write "Gemfile", "source \"https://rubygems.org\"\ngem \"rails\"\n"
    write "config/routes.rb", "Rails.application.routes.draw do\n  get \"/blog/host\", to: \"pages#show\"\nend\n"
  end

  teardown { FileUtils.remove_entry(destination_root) }

  test "new importmap host adds Tailwind and installs both content migration sets" do
    importmap
    output = run_generator %w[--site-name=Meadow --author-name=Riley]
    assert_includes Recorder.host_commands, [ "bundle", "install" ]
    assert_includes Recorder.host_commands, [ "bin/rails", "tailwindcss:install" ]
    assert_includes Recorder.host_commands, [ "bin/rails", "railties:install:migrations", "FROM=active_storage,action_text,open_blog" ]
    assert_includes Recorder.host_commands, [ "bin/rails", "db:migrate" ]
    assert_includes Recorder.host_commands, [ "bin/rails", "open_blog:sample" ]
    assert_file_includes "config/initializers/open_blog.rb", /config.site_name = "Meadow"/, /name: "Riley"/, /body_formats = \[ :markdown \]/
    assert_file_includes "app/assets/tailwind/open_blog/theme.css"
    assert_file_includes "app/assets/tailwind/application.css", '@import "./open_blog/theme.css";'
    assert_file_includes "app/views/layouts/open_blog.html.erb", 'stylesheet_link_tag "tailwind"', "javascript_importmap_tags"
    assert_no_file "app/assets/builds/open_blog/blog.css"
    assert_equal 6, Dir[File.join(destination_root, "app/javascript/controllers/open_blog/*_controller.js")].length
    assert_includes Recorder.host_commands, [ "bin/rails", "open_blog:install_token" ]
    assert_includes output, "MCP: /blog/mcp"
    routes = read("config/routes.rb")
    assert_operator routes.index("/blog/host"), :<, routes.index("mount OpenBlog::Engine")
  end

  test "neither JavaScript setup installs importmap before Stimulus and writes placeholder identities" do
    output = run_generator %w[--skip-tailwind --skip-sample --skip-migrate]
    assert_operator Recorder.host_commands.index([ "bin/rails", "importmap:install" ]), :<, Recorder.host_commands.index([ "bin/rails", "stimulus:install" ])
    refute_includes Recorder.host_commands, [ "bin/rails", "open_blog:install_token" ]
    assert_includes output, "API token deferred"
    refute_includes Recorder.host_commands, [ "bin/rails", "db:migrate" ]
    refute_includes Recorder.host_commands, [ "bin/rails", "open_blog:sample" ]
    refute_includes Recorder.host_commands, [ "bin/rails", "tailwindcss:install" ]
    assert_file_includes "config/initializers/open_blog.rb", '"Example"', '"Ada Example"'
    assert_includes output, "placeholder"
    assert_file_includes "app/assets/stylesheets/open_blog_theme.css"
    assert_file_includes "app/views/layouts/open_blog.html.erb", "open_blog_stylesheets"
    refute_includes read("Gemfile"), "tailwindcss"
  end

  test "existing Tailwind Rails is reused and standalone config files do not decide detection" do
    importmap
    write "app/assets/tailwind/application.css", "@import \"tailwindcss\";\n"
    write "config/tailwind.config.js", "module.exports = {}\n"
    run_generator %w[--skip-sample]
    refute_includes Recorder.host_commands, [ "bin/rails", "tailwindcss:install" ]
    assert_file_includes "app/views/layouts/open_blog.html.erb", 'stylesheet_link_tag "tailwind"'
  end

  test "cssbundling Tailwind4 selects application build and namespaced source files" do
    bundler(tailwind: "^4.1.0")
    write "app/assets/stylesheets/application.tailwind.css", "@import \"tailwindcss\";\n"
    run_generator %w[--skip-sample]
    refute_includes Recorder.host_commands, [ "bin/rails", "tailwindcss:install" ]
    assert_includes Recorder.host_commands, [ "bin/rails", "stimulus:manifest:update" ]
    assert_file_includes "app/assets/tailwind/open_blog/theme.css"
    assert_file_includes "app/assets/stylesheets/application.tailwind.css", '@import "../tailwind/open_blog/theme.css";'
    assert_file_includes "config/initializers/open_blog.rb", /excluded_paths/
    assert_file_includes "app/views/layouts/open_blog.html.erb", 'stylesheet_link_tag "application"', 'javascript_include_tag "application"'
    refute_includes read("app/views/layouts/open_blog.html.erb"), "javascript_importmap_tags"
  end

  test "bundler without Tailwind installs it unless explicitly skipped" do
    bundler
    output = run_generator %w[--skip-sample]
    assert_includes Recorder.host_commands, [ "bin/rails", "tailwindcss:install" ]
    assert_includes Recorder.host_commands, [ "bin/rails", "stimulus:manifest:update" ]
    assert_includes output, "--skip-tailwind"
  end

  test "Tailwind3 falls back without modifying its CSS entrypoint" do
    bundler(tailwind: "^3.4.0")
    write "app/assets/stylesheets/application.tailwind.css", "@tailwind base;\n"
    output = run_generator %w[--skip-sample]
    refute_includes Recorder.host_commands, [ "bin/rails", "tailwindcss:install" ]
    assert_equal "@tailwind base;\n", read("app/assets/stylesheets/application.tailwind.css")
    assert_file_includes "app/views/layouts/open_blog.html.erb", "open_blog_stylesheets"
    assert_includes output, "Tailwind 3"
  end

  test "repeat install is file-identical and preserves changed views without a terminal" do
    importmap
    arguments = %w[--skip-tailwind --skip-sample --site-name=Meadow --author-name=Riley]
    run_generator arguments.dup
    original = snapshot
    run_generator arguments.dup
    assert_equal original, snapshot
    write "app/views/open_blog/posts/show.html.erb", "Custom page\n"
    run_generator arguments.dup
    assert_equal "Custom page\n", read("app/views/open_blog/posts/show.html.erb")
    run_generator arguments + [ "--force" ]
    assert_includes read("app/views/open_blog/posts/show.html.erb"), "open_blog_post_content"
    assert_equal 1, read("config/routes.rb").scan("mount OpenBlog::Engine").length
  end

  test "explicit importmap registrations are appended once and mount-first and formats are honored" do
    importmap
    write "app/javascript/controllers/index.js", 'import { application } from "controllers/application"' + "\n"
    arguments = %w[--skip-tailwind --skip-sample --mount-position=first --mount-at=/journal --body-format=rich_text]
    run_generator arguments.dup
    run_generator arguments.dup
    manifest = read("app/javascript/controllers/index.js")
    assert_equal 6, manifest.scan(/application.register\("open-blog--/).length
    assert_includes manifest, 'from "controllers/open_blog/theme_controller"'
    assert_file_includes "config/initializers/open_blog.rb", /body_formats = \[ :rich_text \]/, /default_body_format = :rich_text/
    routes = read("config/routes.rb")
    assert_operator routes.index("mount OpenBlog::Engine"), :<, routes.index("/blog/host")
    assert_includes routes, 'at: "/journal"'
  end

  test "skipping migration defers the sample on an unprepared database" do
    importmap
    output = run_generator %w[--skip-tailwind --skip-migrate]
    refute_includes Recorder.host_commands, [ "bin/rails", "open_blog:sample" ]
    assert_includes Recorder.host_commands, [ "bin/rails", "open_blog:doctor" ]
    assert_includes output, "Sample deferred"
  end

  test "a locked Tailwind Rails3 installation keeps its legacy pipeline" do
    importmap
    write "Gemfile.lock", "GEM\n  specs:\n    tailwindcss-rails (3.3.1)\n"
    write "app/assets/stylesheets/application.tailwind.css", "@tailwind base;\n"
    run_generator %w[--skip-sample]
    refute_includes Recorder.host_commands, [ "bin/rails", "tailwindcss:install" ]
    assert_file_includes "app/views/layouts/open_blog.html.erb", "open_blog_stylesheets"
  end

  test "host commands preserve argument boundaries and doctor failures do not hide setup reports" do
    installer = OpenBlog::Generators::InstallGenerator.new([], {}, destination_root: destination_root)
    captured = []
    command = ->(*arguments, **options) { captured << [ arguments, options ]; false }
    installer.stub(:system, command) do
      capture(:stdout) { refute installer.send(:run_host_command, "bin/rails", "open_blog:doctor") }
      assert_raises(Thor::Error) { capture(:stdout) { installer.send(:run_host_command, "bundle", "install") } }
    end
    assert_equal [ [ "bin/rails", "open_blog:doctor" ], [ "bundle", "install" ] ], captured.map(&:first)
    assert_equal [ { chdir: destination_root }, { chdir: destination_root } ], captured.map(&:last)
  end

  test "image dependencies follow the configured host processor even when image_processing has no backend dependency" do
    previous = Rails.application.config.active_storage.variant_processor
    importmap
    Rails.application.config.active_storage.variant_processor = :vips
    run_generator %w[--skip-tailwind --skip-sample]
    assert_match(/^gem "ruby-vips"/, read("Gemfile"))
    refute_match(/^gem "mini_magick"/, read("Gemfile"))
    write "Gemfile", "source \"https://rubygems.org\"\ngem \"rails\"\n"
    Rails.application.config.active_storage.variant_processor = :mini_magick
    run_generator %w[--skip-tailwind --skip-sample]
    assert_match(/^gem "mini_magick"/, read("Gemfile"))
    refute_match(/^gem "ruby-vips"/, read("Gemfile"))
  ensure
    Rails.application.config.active_storage.variant_processor = previous
  end

  test "a commented mount does not suppress the live engine route" do
    importmap
    write "config/routes.rb", "Rails.application.routes.draw do\n  # mount OpenBlog::Engine, at: \"/blog\"\nend\n"
    run_generator %w[--skip-tailwind --skip-sample]
    assert_equal 1, read("config/routes.rb").scan(/^  mount OpenBlog::Engine/).length
  end

  test "initializer serializes quotes and interpolation characters as data" do
    importmap
    name = 'A "quoted" #{name} and \\ path'
    run_generator [ "--skip-tailwind", "--skip-sample", "--site-name=#{name}", "--author-name=#{name}" ]
    original = OpenBlog.config
    config = OpenBlog::Configuration.new
    OpenBlog.instance_variable_set(:@config, config)
    load File.join(destination_root, "config/initializers/open_blog.rb")
    assert_equal name, config.site_name
    assert_equal name, config.default_author[:name]
  ensure
    OpenBlog.instance_variable_set(:@config, original)
  end

  private

  def assert_file_includes(path, *patterns)
    assert_file(path, *patterns.map { |pattern| pattern.is_a?(String) ? Regexp.new(Regexp.escape(pattern)) : pattern })
  end

  def importmap
    write "config/importmap.rb", 'pin_all_from "app/javascript/controllers", under: "controllers"' + "\n"
    write "app/javascript/application.js", "import \"controllers\"\n"
    write "app/javascript/controllers/index.js", 'eagerLoadControllersFrom("controllers", application)' + "\n"
  end

  def bundler(tailwind: nil)
    write "package.json", JSON.generate({ "devDependencies" => tailwind ? { "tailwindcss" => tailwind } : {} })
    write "app/javascript/application.js", "import \"./controllers\"\n"
    write "app/javascript/controllers/index.js", "import { application } from \"./application\"\n"
  end

  def write(path, content)
    full_path = File.join(destination_root, path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, content)
  end

  def read(path)
    File.read(File.join(destination_root, path))
  end

  def snapshot
    Dir[File.join(destination_root, "**/*")].select { |path| File.file?(path) }.to_h { |path| [ path.delete_prefix(destination_root), File.binread(path) ] }
  end
end
