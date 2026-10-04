require_relative "../test_helper"
require "rails/generators/test_case"
require "generators/open_blog/views/views_generator"
require "tmpdir"
require "minitest/mock"

class ViewsGeneratorTest < Rails::Generators::TestCase
  tests OpenBlog::Generators::ViewsGenerator

  setup { self.destination_root = Dir.mktmpdir("open-blog-views") }
  teardown { FileUtils.remove_entry(destination_root) }

  test "views refresh preserves changed files unless forced" do
    run_generator
    path = File.join(destination_root, "app/views/open_blog/posts/show.html.erb")
    File.write(path, "A custom article\n")
    run_generator
    assert_equal "A custom article\n", File.read(path)
    run_generator [ "--force" ]
    assert_includes File.read(path), "open_blog_post_content"
  end

  test "views refresh keeps the existing fallback stylesheet choice on a Tailwind host" do
    css = File.join(destination_root, "app/assets/tailwind/application.css")
    FileUtils.mkdir_p(File.dirname(css))
    File.write(css, '@import "tailwindcss";')
    run_generator [ "--skip-tailwind" ]
    run_generator [ "--force" ]
    layout = File.read(File.join(destination_root, "app/views/layouts/open_blog.html.erb"))
    assert_includes layout, "open_blog_stylesheets"
    refute_includes layout, 'stylesheet_link_tag "tailwind"'
    run_generator [ "--force", "--no-skip-tailwind" ]
    layout = File.read(File.join(destination_root, "app/views/layouts/open_blog.html.erb"))
    assert_operator layout.index("<%= open_blog_theme_stylesheets %>"), :<, layout.index('stylesheet_link_tag "tailwind"')
    run_generator [ "--force" ]
    assert_equal layout, File.read(File.join(destination_root, "app/views/layouts/open_blog.html.erb"))
  end

  test "interactive views refresh delegates changed files to the conflict prompt" do
    run_generator
    path = File.join(destination_root, "app/views/open_blog/posts/show.html.erb")
    File.write(path, "A custom article\n")
    collisions = []
    shell = Thor::Shell::Basic.new
    instance = OpenBlog::Generators::ViewsGenerator.new([], {}, destination_root: destination_root, shell: shell)
    $stdin.stub(:tty?, true) do
      shell.stub(:file_collision, ->(file) { collisions << file; false }) do
        capture(:stdout) { instance.invoke_all }
      end
    end
    assert_equal [ path ], collisions
    assert_equal "A custom article\n", File.read(path)
  end
end
