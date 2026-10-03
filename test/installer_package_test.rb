require_relative "test_helper"
require "rubygems/package"
require "tmpdir"
require "stringio"
load File.expand_path("../bin/test-installer", __dir__)

class InstallerPackageTest < ActiveSupport::TestCase
  class Harness < InstallerHarness
    attr_reader :commands
    attr_accessor :installation
    def initialize(app, package)
      @app, @options, @root, @commands = app, { gem: package }, "/source/checkout", []
    end
    def capture(*)
      installation.to_json
    end
    def command(*args, **options)
      @commands << args
    end
  end

  setup { @directory = Dir.mktmpdir("installer-package-test") }
  teardown { FileUtils.remove_entry(@directory) }

  test "package mode vendors exact artifact and requests the packaged version without a path source" do
    package = build_package("open_blog", "9.8.7")
    app = File.join(@directory, "host")
    FileUtils.mkdir_p(app)
    File.write(File.join(app, "Gemfile"), "source 'https://rubygems.org'\n")
    harness = Harness.new(app, package)
    harness.send(:install_blog)
    assert_equal File.binread(package), File.binread(File.join(app, "vendor/cache/open_blog-9.8.7.gem"))
    assert_includes File.read(File.join(app, "Gemfile")), 'gem "open_blog", "= 9.8.7"'
    refute_includes File.read(File.join(app, "Gemfile")), "path:"
    assert_includes harness.commands, [ "bundle", "config", "set", "--local", "path", "vendor/bundle" ]
    assert_includes harness.commands, [ "bundle", "install" ]
    refute harness.commands.flatten.include?("--path")
  end

  test "a different gem is refused before host Gemfile changes" do
    package = build_package("another_gem", "1.0.0")
    app = File.join(@directory, "host")
    FileUtils.mkdir_p(app)
    gemfile = File.join(app, "Gemfile")
    File.write(gemfile, "source 'https://rubygems.org'\n")
    assert_raises(RuntimeError) { Harness.new(app, package).send(:install_blog) }
    assert_equal "source 'https://rubygems.org'\n", File.read(gemfile)
  end


  test "runtime verification rejects path sources wrong versions and external installations" do
    package = build_package("open_blog", "9.8.7")
    app = File.join(@directory, "host")
    installed = File.join(app, "vendor/bundle/gems/open_blog-9.8.7")
    FileUtils.mkdir_p(installed)
    Gem::Package.new(package).extract_files(installed)
    File.write(File.join(app, "Gemfile"), "source 'https://rubygems.org'\n")
    harness = Harness.new(app, package)
    harness.send(:install_blog)
    receipt = { version: "9.8.7", source: "Bundler::Source::Rubygems", path: installed }
    harness.installation = receipt
    harness.send(:verify_package_installation)
    [ { source: "Bundler::Source::Path" }, { version: "9.8.6" }, { path: @directory } ].each do |mismatch|
      harness.installation = receipt.merge(mismatch)
      assert_raises(RuntimeError) { harness.send(:verify_package_installation) }
    end
    harness.installation = receipt
    File.write(File.join(installed, "payload.rb"), "changed")
    assert_raises(RuntimeError) { harness.send(:verify_package_installation) }
    File.delete(File.join(installed, "payload.rb"))
    assert_raises(RuntimeError) { harness.send(:verify_package_installation) }
  end

  private

  def build_package(name, version)
    File.write(File.join(@directory, "payload.rb"), "# packaged bytes\n")
    spec = Gem::Specification.new do |gem|
      gem.name, gem.version, gem.summary, gem.authors, gem.files = name, version, "Harness fixture", [ "Test" ], [ "payload.rb" ]
    end
    path = File.join(@directory, "input.gem")
    capture_io { Dir.chdir(@directory) { Gem::Package.build(spec, true, false, path) } }
    path
  end
end
