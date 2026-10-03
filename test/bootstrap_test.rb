require "minitest/autorun"
require "open3"
require "rubygems/package"
require "tmpdir"

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
    assert_equal "0.1.0.dev\n", stdout
  end

  def test_gemspec_declares_identity_and_supported_versions
    spec = Gem::Specification.load(File.join(ROOT, "open_blog.gemspec"))
    refute_nil spec
    assert_equal "open_blog", spec.name
    assert_equal "0.1.0.dev", spec.version.to_s
    assert_equal [ "TechWright Labs" ], spec.authors
    assert_equal [ "engineering@techwright.io" ], Array(spec.email)
    assert_equal [ "MIT" ], spec.licenses
    assert_equal REPOSITORY, spec.homepage
    assert_equal REPOSITORY, spec.metadata["source_code_uri"]
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
      files = Gem::Package.new(artifact).spec.files
      %w[lib/open_blog.rb lib/open_blog/version.rb LICENSE.txt README.md CHANGELOG.md].each do |file|
        assert_includes files, file
      end
      %w[test/ docs/].each do |prefix|
        refute files.any? { |file| file.start_with?(prefix) }, "packaged development files under #{prefix}"
      end
      assert files.all? { |file| file.match?(%r{\A(?:lib/|app/|config/|db/|skills/|LICENSE\.txt\z|README\.md\z|CHANGELOG\.md\z)}) }
    end
  end
end
