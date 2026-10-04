require_relative "test_helper"
require "tmpdir"
require "fileutils"
require "minitest/mock"

class DoctorTest < ActiveSupport::TestCase
  setup do
    @directory = Dir.mktmpdir("open-blog-doctor")
    @root = Pathname(@directory)
    @config = OpenBlog::Configuration.new
    @config.site_name = "Field Notes"
    @config.default_author = { name: "Alex Green", type: :person }
    @config.publisher = { name: "Field Notes" }
    @config.public_base_url = "https://notes.example"
    @config.authenticate = ->(_request) { nil }
    @config.rate_limit_store = ActiveSupport::Cache::MemoryStore.new
    @config.sign_in_destinations = []
    @config.policy_urls = %i[responsible_party corrections editorial ai_use].to_h { |key| [ key, "https://notes.example/#{key}" ] }
    @application = Struct.new(:root, :routes, :config, :assets, :paths).new(@root, Rails.application.routes,
      Struct.new(:active_storage, :active_job).new(Rails.application.config.active_storage, Struct.new(:queue_adapter).new(:solid_queue)), Rails.application.assets, Rails.application.paths)
    FileUtils.cp_r(OpenBlog::Engine.root.join("lib/generators/open_blog/install/templates/views"), @root.join("app").tap(&:mkpath).join("views"))
    write("app/assets/stylesheets/open_blog_theme.css", " :root { --ob-surface: white; }")
    write("config/initializers/open_blog.rb", "config.primary_list_type = :categories\nconfig.sign_in_destinations = []\n")
    write("config/importmap.rb", 'pin_all_from Rails.root.join("app/javascript/controllers"), under: "controllers"')
    write("app/javascript/application.js", 'import "controllers"')
    write("app/javascript/controllers/index.js", 'import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"; eagerLoadControllersFrom("controllers", application)')
    FileUtils.cp_r(OpenBlog::Engine.root.join("app/assets/javascripts/open_blog/controllers"), @root.join("app/javascript/controllers/open_blog"))
  end

  teardown do
    FileUtils.remove_entry(@directory)
  end

  test "every named check reports a bootable complete installation without modifying content" do
    checks = OpenBlog::Doctor.run(application: @application, config: @config, http_get: ->(_url) { 200 })
    assert_equal [ "Configuration", "Migrations", "Route", "Views", "Theme", "JavaScript", "Authentication", "Rate limit", "Jobs", "Storage", "Policy pages", "Records", "Declarations" ], checks.pluck(:name)
    assert checks.all? { |check| check[:status] == "ok" }, checks.inspect
    assert checks.all? { |check| check.keys.sort == %i[message name status] && check[:message].present? }
  end

  test "authentication accepts only active tokens when there is no host hook" do
    @config.authenticate = nil
    assert_equal "warning", check("Authentication")[:status]
    token, = OpenBlog::ApiToken.generate(name: "Diagnostics")
    assert_equal "ok", check("Authentication")[:status]
    token.update!(revoked_at: Time.current)
    assert_equal "warning", check("Authentication")[:status]
    token.update!(revoked_at: nil, expires_at: 1.second.ago)
    assert_equal "warning", check("Authentication")[:status]
  end

  test "configuration reports invalid and placeholder values without aborting remaining checks" do
    @config.site_name = nil
    assert_equal "error", check("Configuration")[:status]
    @config.site_name = "Example"
    assert_equal "warning", check("Configuration")[:status]
    @config.site_name = "Field Notes"
    @config.public_base_url = nil
    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("production")) { assert_equal "error", check("Configuration")[:status] }
  end

  test "missing Action Text and content tables are errors while records check remains reportable" do
    connection = ActiveRecord::Base.connection
    original = connection.method(:data_source_exists?)
    connection.stub(:data_source_exists?, ->(name) { name.to_s == "action_text_rich_texts" ? false : original.call(name) }) do
      assert_equal "error", check("Migrations")[:status]
      assert_includes check("Migrations")[:message], "action_text_rich_texts"
    end
    connection.stub(:data_source_exists?, ->(name) { name.to_s == "open_blog_posts" ? false : original.call(name) }) do
      assert_equal "error", check("Migrations")[:status]
      assert_equal "warning", check("Records")[:status]
    end
  end

  test "mount absence and host routes hidden by the engine are detected from the route set" do
    routes = ActionDispatch::Routing::RouteSet.new
    @application.routes = routes
    routes.draw { get "/elsewhere", to: "pages#index" }
    assert_equal "error", check("Route")[:status]
    routes.draw do
      mount OpenBlog::Engine => "/blog"
      get "/blog/custom", to: "pages#index"
    end
    assert_equal "error", check("Route")[:status]
    routes.draw do
      get "/blog/custom", to: "pages#index"
      mount OpenBlog::Engine => "/blog"
      get "/blogger", to: "pages#index"
    end
    assert_equal "ok", check("Route")[:status]
  end

  test "views follow copied partials but reject missing helpers and variant content covers" do
    path = @root.join("app/views/open_blog/posts/_faq.html.erb")
    path.write("No FAQ helper")
    assert_equal "error", check("Views")[:status]
    path.write("<%= open_blog_faq(post) %>")
    path = @root.join("app/views/open_blog/posts/show.html.erb")
    path.write(path.read.sub("open_blog_cover(post)", "image_tag post.cover_image.file.variant(resize_to_fill: [600, 400])"))
    assert_equal "error", check("Views")[:status]
    assert_includes check("Views")[:message], "cover"
  end

  test "theme detects missing host tokens imports builds and global asset leakage" do
    @root.join("app/assets/stylesheets/open_blog_theme.css").delete
    assert_equal "error", check("Theme")[:status]
    write("app/assets/stylesheets/open_blog_theme.css", ":root { --ob-surface: white; }")
    write("app/views/layouts/application.html.erb", "<%= stylesheet_link_tag :all %>")
    assert_equal "warning", check("Theme")[:status]
    @root.join("app/views/layouts/application.html.erb").delete
    write("app/assets/tailwind/application.css", '@import "tailwindcss";')
    assert_equal "ok", check("Theme")[:status]
    layout = @root.join("app/views/layouts/open_blog.html.erb")
    layout.write(layout.read.sub("open_blog_stylesheets", 'stylesheet_link_tag "tailwind"'))
    assert_equal "error", check("Theme")[:status]
  end

  test "theme names the preset refuses an unknown one and accepts none" do
    OpenBlog::Themes.names.each do |name|
      @config.theme = name
      assert_equal({ name: "Theme", status: "ok", message: "Theme #{name}: sources and compiled stylesheets are available." }, check("Theme"))
    end
    @config.theme = :none
    assert_equal "ok", check("Theme")[:status]
    assert_includes check("Theme")[:message], "Theme none"
    @config.theme_colors = { accent: "#1d4ed8" }
    assert_equal "warning", check("Theme")[:status]
    assert_includes check("Theme")[:message], "theme_colors has no effect with theme :none"
    @config.theme = :slate
    assert_equal "error", check("Theme")[:status]
    assert_includes check("Theme")[:message], "theme must be :signal, :editorial, :ink, :none"
    @config.theme = :signal
    @config.theme_colors = { accent: "teal" }
    assert_equal "error", check("Theme")[:status]
    assert_includes check("Theme")[:message], "theme_colors.accent"
  end

  test "theme warns for each contrast pair an override takes below the minimum in each mode" do
    @config.theme = :editorial
    @config.theme_colors = { accent: "#1d4ed8", dark: { accent: "#93c5fd" } }
    assert_equal "ok", check("Theme")[:status], check("Theme")[:message]
    @config.theme_colors = { text_muted: "#9ca3af", dark: { accent_contrast: "#ffffff", text_muted: "#b9ab9a" } }
    result = check("Theme")
    assert_equal "warning", result[:status]
    preset = OpenBlog::Themes.fetch(:editorial)
    light = OpenBlog::Themes.low_contrast(preset.light.merge("text-muted" => "#9ca3af"))
    dark = OpenBlog::Themes.low_contrast(preset.dark.merge("accent-contrast" => "#ffffff"))
    assert_equal [ %w[text-muted surface], %w[text-muted surface-raised] ], light.map { |pair| pair.first(2) }
    assert_equal [ %w[accent-contrast accent] ], dark.map { |pair| pair.first(2) }
    expected = light.map { |_, background, ratio| "light text_muted on #{background.tr('-', '_')} #{ratio.floor(2)}:1" } +
      dark.map { |_, _, ratio| "dark accent_contrast on accent #{ratio.floor(2)}:1" }
    assert_equal "Theme colours below 4.5:1 contrast: #{expected.join(', ')}.", result[:message]
    @config.theme_colors = { text: "#00000000", dark: { notice_bg: "#ffffff00" } }
    assert_equal "warning", check("Theme")[:status]
    assert_includes check("Theme")[:message], "light text on surface 1.0:1"
    refute_includes check("Theme")[:message], "notice_bg"
    write("app/views/layouts/application.html.erb", "<%= stylesheet_link_tag :all %>")
    assert_includes check("Theme")[:message], "contrast"
    assert_includes check("Theme")[:message], "stylesheet_link_tag :all"
  end

  test "a Tailwind layout must load the preset stylesheet unless the theme is none" do
    write("app/assets/tailwind/application.css", '@import "tailwindcss"; @import "./open_blog/theme.css";')
    write("app/assets/tailwind/open_blog/theme.css", "")
    %w[blog syntax].each do |name|
      FileUtils.cp(OpenBlog::Engine.root.join("lib/generators/open_blog/install/templates/theme/#{name}.css"), @root.join("app/assets/tailwind/open_blog/#{name}.css"))
    end
    layout = @root.join("app/views/layouts/open_blog.html.erb")
    source = layout.read
    layout.write(source.sub("open_blog_stylesheets", 'stylesheet_link_tag "tailwind"'))
    @application.assets = Struct.new(:resolver).new(Struct.new(:found) { def resolve(name) = found.include?(name) }.new(%w[tailwind.css open_blog/themes.css]))
    assert_equal "error", check("Theme")[:status]
    assert_includes check("Theme")[:message], "open_blog_theme_stylesheets"
    @config.theme = :none
    assert_equal "ok", check("Theme")[:status], check("Theme")[:message]
    @config.theme = :ink
    layout.write(source.sub("open_blog_stylesheets", "open_blog_theme_stylesheets %>\n    <%= stylesheet_link_tag \"tailwind\""))
    assert_equal "ok", check("Theme")[:status], check("Theme")[:message]
    @application.assets.resolver.found.delete("open_blog/themes.css")
    assert_equal "error", check("Theme")[:status]
    assert_includes check("Theme")[:message], "open_blog/themes.css"
  end

  test "a Tailwind host with component styles from an earlier version gets a warning" do
    write("app/assets/tailwind/application.css", '@import "tailwindcss"; @import "./open_blog/theme.css";')
    %w[theme syntax].each { |name| write("app/assets/tailwind/open_blog/#{name}.css", "") }
    write("app/assets/tailwind/open_blog/blog.css", ".ob-faq-entry + .ob-faq-entry { margin-top: 1rem; }")
    layout = @root.join("app/views/layouts/open_blog.html.erb")
    layout.write(layout.read.sub("open_blog_stylesheets", "open_blog_theme_stylesheets %>\n    <%= stylesheet_link_tag \"tailwind\""))
    @application.assets = Struct.new(:resolver).new(Struct.new(:found) { def resolve(name) = found.include?(name) }.new(%w[tailwind.css open_blog/themes.css]))
    result = check("Theme")
    assert_equal "warning", result[:status]
    assert_includes result[:message], "app/assets/tailwind/open_blog/blog.css has no preset or collapsed FAQ rules"
    assert_includes result[:message], "Delete it and theme.css in the same directory, then run bin/rails generate open_blog:install."
    @config.faq_collapsed = false
    assert_includes check("Theme")[:message], "blog.css has no preset rules"
    @config.theme = :none
    assert_equal "ok", check("Theme")[:status], check("Theme")[:message]
    @config.faq_collapsed = true
    assert_includes check("Theme")[:message], "blog.css has no collapsed FAQ rules. Delete it, then run"
    FileUtils.cp(OpenBlog::Engine.root.join("lib/generators/open_blog/install/templates/theme/blog.css"), @root.join("app/assets/tailwind/open_blog/blog.css"))
    @config.theme = :signal
    result = check("Theme")
    assert_equal "warning", result[:status]
    assert_equal "app/assets/tailwind/open_blog/syntax.css has no preset rules, so code blocks show light-mode syntax colours on the dark code background. Run bin/rails open_blog:syntax_css.", result[:message]
    @config.theme = :none
    assert_equal "ok", check("Theme")[:status], check("Theme")[:message]
    @config.theme = :signal
    OpenBlog::SyntaxCss.write(root: @root, theme: "gruvbox")
    assert_includes @root.join("app/assets/tailwind/open_blog/syntax.css").read, ":root[data-ob-theme] .ob-highlight"
    assert_equal "ok", check("Theme")[:status], check("Theme")[:message]
  end

  test "JavaScript follows the blog entry point rather than an unrelated controller index" do
    layout = @root.join("app/views/layouts/open_blog.html.erb")
    layout.write(layout.read.sub("javascript_importmap_tags", 'javascript_importmap_tags "marketing"'))
    write("app/javascript/marketing.js", 'import "@hotwired/stimulus"')
    assert_equal "error", check("JavaScript")[:status]
    write("app/javascript/marketing.js", 'import "controllers"')
    assert_equal "ok", check("JavaScript")[:status]
    @root.join("app/javascript/controllers/open_blog/share_controller.js").delete
    assert_equal "error", check("JavaScript")[:status]
  end

  test "JavaScript uses curated map pins and refuses an unverifiable dynamic entry point" do
    layout = @root.join("app/views/layouts/open_blog.html.erb")
    original = layout.read
    layout.write(original.sub("javascript_importmap_tags", 'javascript_importmap_tags "marketing", importmap: Rails.application.importmap_marketing'))
    write("app/javascript/marketing_entry.js", 'import "controllers"')
    write("config/importmap_marketing.rb", "pin \"marketing\", to: \"marketing_entry.js\"\n")
    assert_equal "error", check("JavaScript")[:status]
    write("config/importmap_marketing.rb", "pin \"marketing\", to: \"marketing_entry.js\"\npin_all_from Rails.root.join(\"app/javascript/controllers\"), under: \"controllers\"")
    assert_equal "ok", check("JavaScript")[:status]
    layout.write(original.sub("javascript_importmap_tags", "javascript_importmap_tags current_entrypoint"))
    refute_equal "ok", check("JavaScript")[:status]
  end

  test "JavaScript recognizes bundler explicit registrations only from reachable imports" do
    layout = @root.join("app/views/layouts/open_blog.html.erb")
    layout.write(layout.read.sub("javascript_importmap_tags", 'javascript_include_tag "application", defer: true'))
    files = Dir[@root.join("app/javascript/controllers/open_blog/*_controller.js")]
    source = files.each_with_index.map do |path, index|
      name = File.basename(path, ".js")
      "import Controller#{index} from './open_blog/#{name}';\napplication.register('open-blog--#{name.delete_suffix('_controller').tr('_', '-')}', Controller#{index})"
    end.join("\n")
    write("app/javascript/controllers/index.js", source)
    assert_equal "ok", check("JavaScript")[:status]
    write("app/javascript/application.js", 'import "@hotwired/stimulus"')
    assert_equal "error", check("JavaScript")[:status]
  end

  test "pending copied migrations are detected even when tables exist" do
    pool = ActiveRecord::Base.connection_pool
    schema = pool.schema_migration
    versions = schema.integer_versions
    pool.stub(:schema_migration, schema) do
      schema.stub(:integer_versions, versions.reject { |version| version == 20261003031410 }) do
        assert_equal "error", check("Migrations")[:status]
      end
    end
  end

  test "runtime warning checks stay actionable without future API models" do
    @config.authenticate = nil
    assert_equal "warning", check("Authentication")[:status]
    @config.rate_limit_store.stub(:increment, nil) { assert_equal "warning", check("Rate limit")[:status] }
    @application.config.active_job.queue_adapter = :async
    assert_equal "warning", check("Jobs")[:status]
    @config.image_fetch_policy = :open
    assert_equal "warning", check("Storage")[:status]
    @config.policy_urls[:corrections] = nil
    assert_equal "warning", check("Policy pages")[:status]
    @config.sign_in_destinations = nil
    assert_equal "warning", check("Declarations")[:status]
  end

  test "cache probe initializes a raw counter and removes it afterward" do
    values = {}
    store = Object.new
    store.define_singleton_method(:write) { |key, value, **options| values[key] = options[:raw] ? value : "serialized" }
    store.define_singleton_method(:increment) { |key, amount| values[key].is_a?(Integer) ? values[key] += amount : nil }
    store.define_singleton_method(:delete) { |key| values.delete(key) }
    @config.rate_limit_store = store
    assert_equal "ok", check("Rate limit")[:status]
    assert_empty values
  end

  test "policy probes report failures and records independently recompute content and reader dates" do
    response = OpenBlog::Doctor.run(application: @application, config: @config, http_get: ->(_url) { 404 })
    assert_equal "warning", response.find { |row| row[:name] == "Policy pages" }[:status]
    post = OpenBlog::Publish.call({ title: "Doctor record", body: "Original body" }, actor: "Editor", now: 1.day.ago).post
    assert_equal "ok", check("Records")[:status]
    post.update_columns(body_markdown: "Unrecorded body")
    assert_equal "error", check("Records")[:status]
    post.update_columns(body_markdown: "Original body", modified_at: 2.days.ago)
    assert_equal "error", check("Records")[:status]
  end

  test "published local policies are checked without HTTP and draft policies warn" do
    @config.policy_urls = {}
    pages = create_policy_pages
    probe = ->(*) { flunk "Local policy pages must not trigger HTTP" }
    assert_equal "ok", policy_check(probe)[:status]
    pages.first.update!(status: "draft")
    result = policy_check(probe)
    assert_equal "warning", result[:status]
    assert_includes result[:message], "responsible_party"
  end

  test "configured policy overrides are probed even when a published local page exists" do
    create_policy_pages
    @config.policy_urls = { responsible_party: "https://editor.example/about" }
    requests = []
    result = policy_check(->(url) { requests << url; 404 })
    assert_equal [ "https://editor.example/about" ], requests
    assert_equal "warning", result[:status]
    assert_includes result[:message], "responsible_party: HTTP 404"
    refute_includes result[:message], "corrections"
  end

  test "missing policy table is reported without trying to query or fetch internal pages" do
    @config.policy_urls = {}
    connection = ActiveRecord::Base.connection
    original = connection.method(:data_source_exists?)
    connection.stub(:data_source_exists?, ->(name) { name.to_s == "open_blog_pages" ? false : original.call(name) }) do
      result = policy_check(->(*) { flunk "Missing local pages must not trigger HTTP" })
      assert_equal "warning", result[:status]
      assert_includes result[:message], "open_blog_pages"
      assert_includes check("Migrations")[:message], "open_blog_pages"
    end
  end

  test "policy response only reads headers and has a total deadline" do
    closed = false
    http = Object.new
    http.define_singleton_method(:request) do |_request, &block|
      block.call(Struct.new(:code).new("200"))
      raise "Response body must not be consumed"
    end
    start = lambda do |*_arguments, **_options, &block|
      block.call(http)
    ensure
      closed = true
    end
    doctor = OpenBlog::Doctor.new(application: @application, config: @config, http_get: nil)
    Net::HTTP.stub(:start, start) do
      assert_equal 200, doctor.send(:policy_response, "https://notes.example/policy")
    end
    assert closed
    Timeout.stub(:timeout, ->(seconds, &_block) { assert_equal 3, seconds; raise Timeout::Error }) do
      result = doctor.run.find { |row| row[:name] == "Policy pages" }
      assert_equal "warning", result[:status]
      assert_includes result[:message], "Timeout::Error"
    end
  end

  test "record dates follow adopted baselines and maintenance never advances them" do
    published = 2.years.ago.change(usec: 0)
    modified = published + 3.days
    result = OpenBlog::Adopt.call({ source_system: "doctor-fixture", source_id: "archived", title: "Adopted guide", slug: "adopted-guide",
      body_format: "markdown", body: "Archived text", first_published_at: published, first_published_evidence: "Archive",
      last_modified_at: modified, last_modified_evidence: "Change log" }, actor: "Editor", now: 2.days.ago)
    assert result.success?, result.error&.message
    assert_equal "ok", check("Records")[:status]
    result = OpenBlog::Publish.call({ change: "maintenance" }, post: result.post, actor: "Editor", now: 1.day.ago)
    assert result.success?, result.error&.message
    assert_equal modified, result.post.modified_at
    assert_equal "ok", check("Records")[:status]
  end

  private

  def create_policy_pages
    OpenBlog::Page::KINDS.map do |kind|
      OpenBlog::Page.create!(kind: kind, title: "Editorial information", body_markdown: "Contact the editorial desk.", status: "published")
    end
  end

  def policy_check(probe)
    OpenBlog::Doctor.run(application: @application, config: @config, http_get: probe).find { |row| row[:name] == "Policy pages" }
  end

  def check(name)
    OpenBlog::Doctor.run(application: @application, config: @config, http_get: ->(_url) { 200 }).find { |row| row[:name] == name }
  end

  def write(path, content)
    file = @root.join(path)
    file.dirname.mkpath
    file.write(content)
  end
end
