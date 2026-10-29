require_relative "../test_helper"
require "rails/generators/test_case"
require "generators/open_blog/admin_suite/admin_suite_generator"
require "tmpdir"

class AdminSuiteGeneratorTest < Rails::Generators::TestCase
  tests OpenBlog::Generators::AdminSuiteGenerator
  setup { self.destination_root = Dir.mktmpdir("open-blog-admin") }
  teardown { FileUtils.remove_entry(destination_root) }

  test "writes isolated resources portal and discovery initializer idempotently" do
    host = File.join(destination_root, "app/admin/resources/post_resource.rb")
    FileUtils.mkdir_p(File.dirname(host))
    File.write(host, "class Admin::Resources::PostResource; end\n")
    run_generator
    %w[post category author page].each do |name|
      assert_file "app/admin/resources/open_blog/#{name}_resource.rb", /model ::OpenBlog::#{name.camelize}/
    end
    assert_file "app/admin/portals/open_blog_portal.rb", /class OpenBlogPortal/
    assert_file "config/initializers/open_blog_admin_suite.rb", /resource_globs/, /portal_globs/
    first = snapshot
    run_generator
    assert_equal first, snapshot
    assert_equal "class Admin::Resources::PostResource; end\n", File.read(host)
  end

  test "writes token settings with no grants and keeps customized grants on rerun" do
    run_generator
    assert_file "config/initializers/open_blog_api_tokens.rb", /OpenBlog\.configure/, /YamlGrants\.load/, /api_tokens\.default_lifetime = 90\.days/
    assert_file "config/open_blog.yml", /api_tokens:\n  grants: \{\}/
    assert_nil OpenBlog::ApiTokens::YamlGrants.load(File.join(destination_root, "config/open_blog.yml")).grants_for("admin:1")
    yaml = File.join(destination_root, "config/open_blog.yml")
    File.write(yaml, "api_tokens:\n  grants:\n    admin:7:\n      manage: [own]\n      scopes: [read]\n")
    initializer = File.join(destination_root, "config/initializers/open_blog_api_tokens.rb")
    File.write(initializer, "# edited\n")
    run_generator
    assert_equal "api_tokens:\n  grants:\n    admin:7:\n      manage: [own]\n      scopes: [read]\n", File.read(yaml)
    assert_equal "# edited\n", File.read(initializer)
  end

  test "generated token initializer loads and leaves identity unwired" do
    run_generator
    original = OpenBlog.config.api_tokens.policy
    load File.join(destination_root, "config/initializers/open_blog_api_tokens.rb")
    assert_respond_to OpenBlog.config.api_tokens.policy, :grants_for
    assert_nil OpenBlog.config.api_tokens.identity
  ensure
    OpenBlog.config.api_tokens.policy = original
  end

  test "generator says tokens stay disabled until identity and grants exist" do
    output = run_generator
    assert_match(/API tokens stay disabled until config\.api_tokens\.identity returns a trusted admin identity and config\/open_blog\.yml grants it access\./, output)
  end

  test "custom directory uses discovery paths while preserving edited resources" do
    run_generator [ "--dir=config/blog_admin" ]
    assert_file "config/blog_admin/resources/open_blog/post_resource.rb"
    assert_file "config/initializers/open_blog_admin_suite.rb", /config\/blog_admin\/resources\/open_blog/, /config\/blog_admin\/portals/
    path = File.join(destination_root, "config/blog_admin/resources/open_blog/post_resource.rb")
    File.write(path, "# Host customizations\n")
    run_generator [ "--dir=config/blog_admin" ]
    assert_equal "# Host customizations\n", File.read(path)
  end

  test "history has display panels and no editable record resources" do
    run_generator
    assert_file "app/admin/resources/open_blog/post_resource.rb", /field :faqs_attributes, type: :open_blog_faq/, /::OpenBlog::AdminSuite.install!/
    %w[revision approval publication baseline faq].each do |name|
      assert_no_file "app/admin/resources/open_blog/#{name}_resource.rb"
    end
    assert_file "app/admin/resources/open_blog/post_resource.rb", /panel :revisions/, /panel :approvals/, /panel :publications/, /panel :baseline/
  end


  test "invalid destinations are rejected before writing files" do
    %w[/tmp/outside ../outside app/admin/*].each do |path|
      error = assert_raises(Thor::Error) do
        OpenBlog::Generators::AdminSuiteGenerator.new([], { dir: path }, destination_root: destination_root).invoke_all
      end
      assert_match(/relative host directory/, error.message)
      assert_empty snapshot
    end
  end

  test "initializer remains loadable without the optional gem" do
    skip "The optional integration bundle loads AdminSuite" if defined?(::AdminSuite)
    run_generator
    load File.join(destination_root, "config/initializers/open_blog_admin_suite.rb")
    assert_nil defined?(::AdminSuite)
    assert_nil defined?(::Admin::Resources::OpenBlog::PostResource)
  end

  private

  def snapshot
    Dir[File.join(destination_root, "**/*")].select { |path| File.file?(path) }.to_h { |path| [ path, File.binread(path) ] }
  end
end
