require_relative "test_helper"
require "open3"
require "tmpdir"

class AdminSuiteOptionalLoadTest < ActiveSupport::TestCase
  test "requiring the gem in the ordinary bundle never loads AdminSuite" do
    root = OpenBlog::Engine.root.to_s
    stdout, stderr, status = Bundler.with_unbundled_env do
      Open3.capture3({ "BUNDLE_GEMFILE" => File.join(root, "Gemfile") }, Gem.ruby, "-rbundler/setup", "-Ilib", "-ropen_blog", "-e", "puts defined?(AdminSuite).inspect", chdir: root)
    end
    assert status.success?, stderr
    assert_equal "nil\n", stdout
  end
end

class AdminSuiteIntegrationTest < ActiveSupport::TestCase
  setup do
    unless Gem.loaded_specs.key?("admin_suite")
      flunk "AdminSuite integration dependency is missing" if ENV["OPEN_BLOG_TEST_ADMIN_SUITE"] == "1"
      skip "Run with gemfiles/admin_suite.gemfile"
    end
    assert_equal "0.6.1", Gem.loaded_specs.fetch("admin_suite").version.to_s
    require_relative "support/admin_suite"
    require "rails/generators"
    require "generators/open_blog/admin_suite/admin_suite_generator"
    @registry = Admin::Base::Resource.registered_resources.dup
    Admin.const_set(:Resources, Module.new) unless Admin.const_defined?(:Resources, false)
    @host_resource_created = !Admin::Resources.const_defined?(:PostResource, false)
    Admin::Resources.const_set(:PostResource, Class.new(Admin::Base::Resource)) if @host_resource_created
    @host_resource = Admin::Resources::PostResource
    @directory = Dir.mktmpdir("open-blog-admin-integration")
    OpenBlog::Generators::AdminSuiteGenerator.start([], destination_root: @directory, shell: Thor::Shell::Basic.new)
    Dir[File.join(@directory, "app/admin/resources/open_blog/*.rb")].sort.each { |path| load path }
    @authentication = AdminSuite.config.authenticate
    AdminSuite.config.authenticate = ->(_) { true }
  end

  teardown do
    AdminSuite.config.authenticate = @authentication if @directory
    Admin::Base::Resource.registered_resources.replace(@registry) if @registry
    Admin::Resources.send(:remove_const, :PostResource) if @host_resource_created
    FileUtils.remove_entry(@directory) if @directory && File.exist?(@directory)
  end

  test "generated initializer boots and eagerly loads in a fresh host without shadowing host resources" do
    dummy = OpenBlog::Engine.root.join("test/dummy")
    FileUtils.cp_r(dummy.join("config/.").to_s, File.join(@directory, "config"))
    FileUtils.cp_r(dummy.join("app/.").to_s, File.join(@directory, "app"))
    controllers = File.join(@directory, "app/controllers")
    FileUtils.mkdir_p(controllers)
    File.write(File.join(controllers, "application_controller.rb"), "class ApplicationController < ActionController::Base; end\n")
    File.write(File.join(@directory, "app/admin/resources/post_resource.rb"), "module Admin; module Resources; class PostResource < ::Admin::Base::Resource; model ::OpenBlog::Category; end; end; end\n")
    File.write(File.join(@directory, "config/initializers/00_existing_admin.rb"), <<~RUBY)
      Rails.application.config.after_initialize do
        require Rails.root.join("app/admin/resources/post_resource.rb") if ENV["OPEN_BLOG_PRELOAD_HOST"] == "1"
      end
    RUBY
    script = <<~RUBY
      require File.join(ENV.fetch("OPEN_BLOG_ADMIN_HOST"), "config/environment")
      abort "host discovery skipped" unless Admin::Base::Resource.registered_resources.any? { |resource| resource.name == "Admin::Resources::PostResource" }
      Rails.application.eager_load!
      AdminSuite::DefinitionLoader.load!(:resources)
      AdminSuite::DefinitionLoader.load!(:portals)
      abort "host collision" unless Admin::Resources::PostResource.model_class == OpenBlog::Category
      abort "missing generated post" unless Admin::Resources::OpenBlog::PostResource.model_class == OpenBlog::Post
      abort "adapter missing" unless AdminSuite::ResourcesController.ancestors.include?(OpenBlog::AdminSuite::ResourceParameters)
      abort "missing portal" unless AdminSuite::PortalRegistry.all.key?(:open_blog)
      puts "booted generated integration"
    RUBY
    %w[0 1].each do |preload|
      stdout, stderr, status = Open3.capture3({ "OPEN_BLOG_ADMIN_HOST" => @directory, "OPEN_BLOG_PRELOAD_HOST" => preload }, Gem.ruby, "-e", script, chdir: @directory)
      assert status.success?, "preload=#{preload}\n#{stdout}\n#{stderr}"
      assert_includes stdout, "booted generated integration"
    end
  end

  test "generated edit form and audit panels render through actual AdminSuite" do
    published = OpenBlog::Publish.call({ title: "Panel article", body: "Body.", faq: [ { question: "Where?", answer: "Here." } ] }, actor: "Editor").post
    status, html = engine_request("/open_blog/open_blog_posts/#{published.id}/edit")
    assert_equal 200, status, html
    document = Nokogiri::HTML5(html)
    assert document.at_css('input[name="post[title]"]')
    assert document.at_css('textarea[name="post[body_markdown]"]')
    assert document.at_css('input[name="post[faqs_attributes][0][question]"]')
    assert document.at_css('textarea[name="post[faqs_attributes][0][answer]"]')
    refute document.at_css('[name*="approvals_attributes"], [name*="revisions_attributes"], [name*="publications_attributes"], [name*="baseline_attributes"]')
    status, html = engine_request("/open_blog/open_blog_posts/#{published.id}")
    assert_equal 200, status, html
    document = Nokogiri::HTML5(html)
    %w[revisions approvals publications baseline].each do |kind|
      refute document.css("a[href]").any? { |link| link["href"].match?(%r{/#{kind}/[^/]+/edit}) }, kind
    end
    assert_includes document.text, published.public_revision.identifier
    assert_includes document.text, "Recent publications"
    refute Admin::Base::Resource.registered_resources.any? { |resource| [ OpenBlog::Approval, OpenBlog::Revision, OpenBlog::Publication, OpenBlog::Baseline ].include?(resource.model_class) }
  end

  test "rich text form round trip preserves body when changing FAQ through native update" do
    previous_formats = OpenBlog.config.body_formats
    OpenBlog.config.body_formats = %i[markdown rich_text]
    published = OpenBlog::Publish.call({ title: "Rich admin article", body_format: "rich_text", body: "<p>A <strong>careful</strong> account.</p>" }, actor: "Editor").post
    original = JSON.parse(published.public_revision.payload).fetch("body")
    status, html = engine_request("/open_blog/open_blog_posts/#{published.id}/edit")
    assert_equal 200, status, html
    document = Nokogiri::HTML5(html)
    input = document.at_css('input[type="hidden"][name="post[rich_body]"]')
    refute_nil input
    assert document.at_css("trix-editor")
    refute document.at_css('[name="post[body_format]"]')
    status, html = engine_request("/open_blog/open_blog_posts/#{published.id}", method: "PATCH", params: {
      post: { rich_body: input["value"], faqs_attributes: { "0" => { question: "Why?", answer: "Care matters.", position: "1" } } }
    })
    assert_equal 302, status, html
    published.reload
    assert_equal original, JSON.parse(published.public_revision.payload).fetch("body")
    assert_equal "Care matters.", published.faqs.sole.answer
  ensure
    OpenBlog.config.body_formats = previous_formats if previous_formats
  end

  test "all four generated names resolve their own models and host authorization still gates writes" do
    entries = {
      "open_blog_categories" => OpenBlog::Category.create!(name: "Admin category"),
      "open_blog_authors" => OpenBlog::Author.create!(name: "Admin author"),
      "open_blog_pages" => OpenBlog::Page.create!(kind: "editorial", title: "Admin policy", body_markdown: "Policy.")
    }
    entries.each do |name, record|
      status, html = engine_request("/open_blog/#{name}/#{record.id}/edit")
      assert_equal 200, status, html
      assert_includes html, record.class.model_name.param_key
    end
    previous = AdminSuite.config.authorize
    AdminSuite.config.authorize = ->(actor:, action:, resource:, record:, context:) { false }
    post = OpenBlog::SaveDraft.call({ title: "Denied edit" }, actor: "Editor").post
    status, = engine_request("/open_blog/open_blog_posts/#{post.id}", method: "PATCH", params: { post: { title: "Forbidden change" } })
    assert_equal 403, status
    assert_equal "Denied edit", post.reload.title
  ensure
    AdminSuite.config.authorize = previous if @directory
  end

  test "actual resource route updates content and FAQ once without host resource collision" do
    published = OpenBlog::Publish.call({ title: "Admin article", body: "Original body." }, actor: "Editor").post
    before_revision = published.revisions.count
    before_publication = published.publications.count
    env = Rack::MockRequest.env_for("/open_blog/open_blog_posts/#{published.id}", method: "PATCH", params: {
      post: { title: "Edited title", body_markdown: "Edited body.", faqs_attributes: { "0" => { question: "Why?", answer: "Because.", position: "1" } } }
    })
    status, _headers, response = AdminSuite::Engine.call(env)
    body = +""
    response.each { |chunk| body << chunk }
    response.close if response.respond_to?(:close)
    assert_equal 302, status, body
    published.reload
    assert_equal "Edited title", published.title
    assert_equal "Edited body.", published.body_markdown
    assert_equal [ [ "Why?", "Because." ] ], published.faqs.pluck(:question, :answer)
    assert_equal before_revision + 1, published.revisions.count
    assert_equal before_publication + 1, published.publications.count
    assert_equal "substantive", published.publications.order(:id).last.entry_type
    assert_nil published.publications.order(:id).last.released_by
    assert_same @host_resource, Admin::Resources::PostResource
  end
  private

  def engine_request(path, method: "GET", params: {})
    status, _headers, response = AdminSuite::Engine.call(Rack::MockRequest.env_for(path, method: method, params: params))
    body = +""
    response.each { |chunk| body << chunk }
    response.close if response.respond_to?(:close)
    [ status, body ]
  end
end
