require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "yaml"
require "open3"
load File.expand_path("../bin/prepare-release", __dir__)

class PrepareReleaseTest < Minitest::Test
  def setup
    @temporary = Dir.mktmpdir("open-blog-prepare-test")
    @directory = File.join(@temporary, "checkout")
    FileUtils.mkdir_p(File.join(@directory, "lib/open_blog"))
    @env = { "GITHUB_REPOSITORY" => "techwright-lab/open-blog", "GITHUB_EVENT_NAME" => "workflow_dispatch",
      "GITHUB_REF" => "refs/heads/main", "RELEASE_VERSION" => "0.2.0", "GITHUB_OUTPUT" => File.join(@temporary, "outputs") }
    @commands, @tags, @prs = [], [], []
    @status = 404
    git("init", "-q", "-b", "main")
    git("config", "user.name", "Release Test")
    git("config", "user.email", "release@example.test")
    git("init", "--bare", "-q", File.join(@temporary, "remote.git"))
    git("remote", "add", "origin", File.join(@temporary, "remote.git"))
    File.write(path("lib/open_blog/version.rb"), "module OpenBlog\n  VERSION = \"0.1.0\"\nend\n")
    File.write(path("CHANGELOG.md"), "# Changelog\n\n## [Unreleased]\n\n### Added\n\n- New reader feature.\n\n## [0.1.0] - 2026-01-01\n\n- Initial release.\n")
    commit
    @preparer = OpenBlogPrepareRelease.new(env: @env, directory: @directory, command: method(:command),
      http: ->(_url) { @status }, today: Date.new(2026, 10, 3))
  end

  def teardown
    FileUtils.remove_entry(@temporary)
  end

  def test_prepares_only_version_and_dated_notes_and_dispatches_real_branch_checks
    @preparer.prepare!
    assert_equal [ "CHANGELOG.md", "lib/open_blog/version.rb" ], git("diff", "--name-only", "#{@main}..HEAD").lines.map(&:strip)
    assert_includes File.read(path("lib/open_blog/version.rb")), 'VERSION = "0.2.0"'
    notes = File.read(path("CHANGELOG.md"))
    assert_includes notes, "## [Unreleased]\n\n## [0.2.0] - 2026-10-03\n\n### Added\n\n- New reader feature."
    assert_includes notes, "## [0.1.0] - 2026-01-01\n\n- Initial release."
    assert_includes git("ls-remote", "origin", "refs/heads/release/0.2.0"), git("rev-parse", "HEAD").strip
    assert_includes @body, "\n\nCI, Installer, and Docs"
    %w[ci.yml installer.yml docs.yml].each do |workflow|
      assert_includes @commands, [ "gh", "workflow", "run", workflow, "--repo", "techwright-lab/open-blog", "--ref", "release/0.2.0" ]
    end
    assert_equal "pull_request=https://github.com/techwright-lab/open-blog/pull/42\n", File.read(@env["GITHUB_OUTPUT"])
  end

  def test_initial_undated_release_can_be_finalized_without_losing_unreleased_notes
    @env["RELEASE_VERSION"] = "0.1.0"
    File.write(path("CHANGELOG.md"), "# Changelog\n\n## [Unreleased]\n\n- Documentation.\n\n## [0.1.0]\n\n### Added\n\n- Initial release.\n")
    commit
    @preparer.prepare!
    notes = File.read(path("CHANGELOG.md"))
    assert_equal 1, notes.scan("## [0.1.0]").length
    assert_includes notes, "## [0.1.0] - 2026-10-03"
    assert_includes notes, "- Documentation.\n\n### Added\n\n- Initial release."
  end

  def test_repeated_preparation_reuses_exact_branch_and_pr_even_on_later_date
    @preparer.prepare!
    release_sha = git("rev-parse", "HEAD").strip
    git("checkout", "main")
    @prs = [ { "url" => "https://github.com/techwright-lab/open-blog/pull/42", "state" => "OPEN" } ]
    @commands.clear
    next_day = OpenBlogPrepareRelease.new(env: @env, directory: @directory, command: method(:command),
      http: ->(_url) { @status }, today: Date.new(2026, 10, 4))
    next_day.prepare!
    assert_includes git("ls-remote", "origin", "refs/heads/release/0.2.0"), release_sha
    assert_empty git("status", "--porcelain")
    refute @commands.any? { |args| args[0, 3] == [ "git", "push", "origin" ] || args[0, 3] == [ "gh", "pr", "create" ] }
  end

  def test_branch_with_different_content_is_never_overwritten
    @preparer.prepare!
    File.write(path("unexpected.txt"), "another contributor's work")
    git("add", ".")
    git("commit", "--amend", "--no-edit", "-q")
    git("push", "--force", "origin", "HEAD:refs/heads/release/0.2.0")
    existing = git("rev-parse", "HEAD").strip
    git("checkout", "main")
    error = assert_raises(OpenBlogPrepareRelease::Refusal) { @preparer.prepare! }
    assert_includes error.message, "different contents"
    assert_includes git("ls-remote", "origin", "refs/heads/release/0.2.0"), existing
  end

  def test_diverged_branch_parent_and_closed_pull_request_are_refused
    @preparer.prepare!
    @prs = [ { "url" => "https://github.com/techwright-lab/open-blog/pull/42", "state" => "CLOSED" } ]
    git("checkout", "main")
    error = assert_raises(OpenBlogPrepareRelease::Refusal) { @preparer.prepare! }
    assert_includes error.message, "closed or merged"
    git("checkout", "release/0.2.0")
    File.write(path("another.txt"), "Additional work")
    git("add", ".")
    git("commit", "-qm", "Another change")
    git("push", "origin", "HEAD:refs/heads/release/0.2.0")
    git("checkout", "main")
    error = assert_raises(OpenBlogPrepareRelease::Refusal) { @preparer.prepare! }
    assert_includes error.message, "diverged"
  end

  def test_public_collisions_failed_lookups_downgrades_and_invalid_identity_refuse_before_writes
    [ 200, 429, 500 ].each do |status|
      @status = status
      assert_raises(OpenBlogPrepareRelease::Refusal) { @preparer.prepare! }
      assert_empty git("status", "--porcelain")
    end
    @status = 404
    { "GITHUB_REPOSITORY" => "another/repo", "GITHUB_EVENT_NAME" => "push", "GITHUB_REF" => "refs/heads/topic",
      "RELEASE_VERSION" => "0.0.9" }.each do |key, value|
      original = @env[key]
      @env[key] = value
      assert_raises(OpenBlogPrepareRelease::Refusal) { @preparer.prepare! }
      @env[key] = original
    end
    [ "0.2.0", "0.3.0" ].each do |version|
      @tags = [ { "ref" => "refs/tags/v#{version}" } ]
      assert_raises(OpenBlogPrepareRelease::Refusal) { @preparer.prepare! }
    end
    assert_empty git("status", "--porcelain")
  end

  def test_empty_notes_and_reusing_dated_version_are_refused
    [ "## [Unreleased]\n\n### Added\n", "## [0.1.0]\n- Notes\n" ].each do |notes|
      File.write(path("CHANGELOG.md"), notes)
      commit
      assert_raises(OpenBlogPrepareRelease::Refusal) { @preparer.prepare! }
      assert_empty git("status", "--porcelain")
    end
    File.write(path("CHANGELOG.md"), "## [Unreleased]\n\n## [0.1.0] - 2026-01-01\n- Initial\n")
    commit
    @env["RELEASE_VERSION"] = "0.1.0"
    assert_raises(OpenBlogPrepareRelease::Refusal) { @preparer.prepare! }
  end

  def test_workflow_has_only_manual_trigger_and_permissions_for_pr_and_check_dispatch
    workflow = YAML.load_file(File.expand_path("../.github/workflows/prepare-release.yml", __dir__))
    assert_equal [ "workflow_dispatch" ], (workflow["on"] || workflow[true]).keys
    job = workflow.fetch("jobs").fetch("prepare")
    assert_equal "write", job.fetch("permissions").fetch("pull-requests")
    assert_equal "write", job.fetch("permissions").fetch("actions")
    refute job.fetch("permissions").key?("id-token")
    assert job.fetch("steps").any? { |step| step.fetch("run", "").include?("ruby bin/prepare-release") }
  end

  private

  def path(file) = File.join(@directory, file)
  def git(*args) = execute("git", *args)

  def commit
    git("add", ".")
    git("commit", "-qm", "Fixture")
    @main = git("rev-parse", "HEAD").strip
  end

  def execute(*args)
    stdout, stderr, status = Open3.capture3(*args, chdir: @directory)
    raise stderr unless status.success?
    stdout
  end

  def command(*args)
    @commands << args
    return execute(*args) unless args.first == "gh"
    case args[1, 2]
    when [ "pr", "list" ] then JSON.generate(@prs)
    when [ "pr", "create" ]
      @body = File.read(args[args.index("--body-file") + 1])
      "https://github.com/techwright-lab/open-blog/pull/42\n"
    when [ "workflow", "run" ] then ""
    else
      case args.fetch(2)
      when /commits\/main$/ then JSON.generate("sha" => @main)
      when /matching-refs/ then JSON.generate(@tags)
      else raise "Unexpected command: #{args.inspect}"
      end
    end
  end
end
