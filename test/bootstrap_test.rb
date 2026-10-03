require "minitest/autorun"
require "open3"
require "rubygems/package"
require "tmpdir"
require_relative "../lib/open_blog/version"

class BootstrapTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  REPOSITORY = "https://github.com/techwright-lab/open-blog"

  def test_entry_point_loads_version_and_runtime_dependencies
    script = <<~RUBY
      require "open_blog"
      puts OpenBlog::VERSION
      abort "missing runtime dependency" unless defined?(Rails) && defined?(Commonmarker) && defined?(Rouge) && defined?(MCP)
    RUBY
    stdout, stderr, status = Open3.capture3(Gem.ruby, "-Ilib", "-e", script, chdir: ROOT)

    assert status.success?, stderr
    assert_equal "#{OpenBlog::VERSION}\n", stdout
  end

  def test_gemspec_declares_identity_and_supported_versions
    spec = Gem::Specification.load(File.join(ROOT, "open_blog.gemspec"))
    refute_nil spec
    assert_equal "open_blog", spec.name
    assert_equal OpenBlog::VERSION, spec.version.to_s
    assert_match(/\A\d+\.\d+\.\d+\z/, spec.version.to_s)
    assert_operator spec.version, :>=, Gem::Version.new("0.1.0")
    assert_equal [ "TechWright Labs" ], spec.authors
    assert_equal [ "engineering@techwright.io" ], Array(spec.email)
    assert_equal [ "MIT" ], spec.licenses
    assert_equal REPOSITORY, spec.homepage
    assert_equal REPOSITORY, spec.metadata["source_code_uri"]
    assert_equal "https://techwright-lab.github.io/open-blog/", spec.metadata["documentation_uri"]
    assert_equal "#{REPOSITORY}/blob/main/CHANGELOG.md", spec.metadata["changelog_uri"]
    assert_equal "true", spec.metadata["rubygems_mfa_required"]
    assert_equal Gem::Requirement.new(">= 3.2", "< 4.1"), spec.required_ruby_version
    expected = {
      "rails" => [ ">= 8.0", "< 9.0" ],
      "commonmarker" => [ ">= 2.8", "< 3" ],
      "rouge" => [ ">= 4.7", "< 6" ],
      "mcp" => [ ">= 1.6", "< 2" ],
      "json" => [ ">= 2.3", "< 3" ]
    }.transform_values { |requirements| Gem::Requirement.new(*requirements) }
    assert_equal expected, spec.runtime_dependencies.to_h { |dependency| [ dependency.name, dependency.requirement ] }
    %w[tailwindcss-ruby pg sqlite3 rubocop-rails-omakase capybara selenium-webdriver].each do |name|
      assert_includes spec.development_dependencies.map(&:name), name
    end
  end

  def test_gem_build_is_warning_free_and_packages_only_distributable_files
    Dir.mktmpdir("open-blog-package") do |directory|
      artifact = File.join(directory, "open_blog.gem")
      stdout, stderr, status = Open3.capture3(Gem.ruby, "-S", "gem", "build", "open_blog.gemspec", "--output", artifact, chdir: ROOT)

      assert status.success?, "#{stdout}\n#{stderr}"
      refute_match(/warning/i, "#{stdout}\n#{stderr}")
      package = Gem::Package.new(artifact)
      assert_equal OpenBlog::VERSION, package.spec.version.to_s
      files = package.contents
      %w[lib/open_blog.rb lib/open_blog/version.rb LICENSE.txt README.md CHANGELOG.md].each do |file|
        assert_includes files, file
      end
      %w[
        app/assets/builds/open_blog/blog.css
        lib/generators/open_blog/install/templates/theme/open_blog_theme.css
        lib/generators/open_blog/install/templates/sample_cover.png
        lib/generators/open_blog/install/templates/views/open_blog/posts/show.html.erb
        lib/generators/open_blog/admin_suite/templates/post_resource.rb.tt
        lib/open_blog/admin_suite.rb
        skills/open-blog-install/SKILL.md skills/open-blog-publish/SKILL.md
        skills/open-blog-update/SKILL.md skills/open-blog-adopt/SKILL.md
        skills/open-blog-policy-pages/SKILL.md skills/open-blog-report/SKILL.md
      ].each { |file| assert_includes files, file }
      %w[test/ docs/ .github/ gemfiles/].each do |prefix|
        refute files.any? { |file| file.start_with?(prefix) }, "packaged development files under #{prefix}"
      end
      assert files.all? { |file| file.match?(%r{\A(?:lib/|app/|config/|db/|skills/|LICENSE\.txt\z|README\.md\z|CHANGELOG\.md\z)}) }
    end
  end
end
