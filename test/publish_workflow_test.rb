require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "yaml"
require "open3"
load File.expand_path("../bin/release-check", __dir__)

class PublishWorkflowTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir("open-blog-release-test")
    @env = { "GITHUB_REPOSITORY" => "techwright-lab/open-blog", "GITHUB_EVENT_NAME" => "workflow_dispatch",
      "GITHUB_REF" => "refs/heads/main", "RELEASE_VERSION" => "0.1.0", "RUNNER_TEMP" => @directory,
      "GITHUB_OUTPUT" => File.join(@directory, "outputs") }
    FileUtils.mkdir_p(File.join(@directory, "lib/open_blog"))
    git("init", "-q")
    git("config", "user.name", "Release Test")
    git("config", "user.email", "release@example.test")
    commit_version("0.1.0.dev")
    commit_version("0.1.0")
    @env["RELEASE_SHA"] = git("rev-parse", "HEAD").strip
    @main = @env.fetch("RELEASE_SHA")
    @runs = %w[ci.yml installer.yml docs.yml].to_h { |workflow| [ workflow, [ workflow_run(workflow) ] ] }
    @tags = []
    @releases = []
    @commands = []
    @gate = OpenBlogRelease.new(env: @env, directory: @directory, command: method(:command))
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_preflight_requires_exact_main_successful_push_runs_and_release_notes
    @gate.verify!
    outputs = File.read(@env.fetch("GITHUB_OUTPUT"))
    assert_includes outputs, "version=0.1.0"
    assert_includes outputs, "source_date_epoch=#{git('show', '-s', '--format=%ct', 'HEAD').strip}"
    assert_equal "- Ship the reader.\n", File.read(File.join(@directory, "open-blog-release-notes.md"))
    %w[ci.yml installer.yml docs.yml].each do |workflow|
      assert @commands.any? { |args| args.join.include?("workflows/#{workflow}/runs?head_sha=#{@main}&event=push&branch=main") }
    end
  end

  def test_dispatch_repository_ref_sha_and_version_fail_closed
    { "GITHUB_REPOSITORY" => "another/open-blog", "GITHUB_EVENT_NAME" => "push",
      "GITHUB_REF" => "refs/heads/topic", "RELEASE_SHA" => "a" * 40,
      "RELEASE_VERSION" => "0.1.0.dev" }.each do |key, value|
      original = @env[key]
      @env[key] = value
      assert_raises(OpenBlogRelease::Refusal, key) { @gate.verify! }
      @env[key] = original
    end
    @main = "b" * 40
    assert_raises(OpenBlogRelease::Refusal) { @gate.verify! }
  end

  def test_each_workflow_must_have_a_completed_successful_push_for_this_repository_and_head
    [ { "conclusion" => "failure" }, { "status" => "in_progress" }, { "event" => "pull_request" },
      { "head_branch" => "topic" }, { "head_sha" => "c" * 40 },
      { "head_repository" => { "full_name" => "another/open-blog" } } ].each do |change|
      %w[ci.yml installer.yml docs.yml].each do |workflow|
        @runs[workflow] = [ workflow_run(workflow).merge(change) ]
        assert_raises(OpenBlogRelease::Refusal, "#{workflow}: #{change}") { @gate.verify! }
        @runs[workflow] = [ workflow_run(workflow) ]
      end
    end
    @runs["ci.yml"] << workflow_run("ci.yml").merge("id" => 2, "conclusion" => "failure")
    assert_raises(OpenBlogRelease::Refusal) { @gate.verify! }
    @runs["ci.yml"] = []
    assert_raises(OpenBlogRelease::Refusal) { @gate.verify! }
  end

  def test_later_documentation_commits_are_releasable_but_invalid_notes_and_tags_stop_release
    commit_version("0.1.0")
    sync_evidence
    @gate.verify!
    git("reset", "--hard", "HEAD^")
    sync_evidence
    [ "## [Unreleased]\n- Later.\n", "## [0.1.0]\n\n### Added\n", "## [0.1.0]\n- One\n## [0.1.0]\n- Two\n" ].each do |notes|
      File.write(File.join(@directory, "CHANGELOG.md"), notes)
      amend_notes
      assert_raises(OpenBlogRelease::Refusal) { @gate.verify! }
    end
    File.write(File.join(@directory, "CHANGELOG.md"), "## [0.1.0] - 2026-01-01\n- Ship the reader.\n")
    amend_notes
    @tags = [ { "ref" => "refs/tags/v0.1.0", "object" => { "type" => "commit", "sha" => "d" * 40 } } ]
    assert_raises(OpenBlogRelease::Refusal) { @gate.verify! }
    @tags.first["object"]["sha"] = @main
    @gate.verify!
  end

  def test_older_versions_and_undated_invalid_or_future_release_notes_are_refused
    @tags = [ { "ref" => "refs/tags/v0.2.0", "object" => { "type" => "commit", "sha" => "d" * 40 } } ]
    assert_raises(OpenBlogRelease::Refusal) { @gate.verify! }
    @tags = []
    [ "## [0.1.0]", "## [0.1.0] - 2026-02-30", "## [0.1.0] - 2999-01-01" ].each do |heading|
      File.write(File.join(@directory, "CHANGELOG.md"), "#{heading}\n- Notes\n")
      amend_notes
      assert_raises(OpenBlogRelease::Refusal) { @gate.verify! }
    end
  end

  def test_artifact_build_is_reproducible_and_existing_bytes_must_match
    File.write(File.join(@directory, "open_blog.gemspec"), <<~SPEC)
      Gem::Specification.new do |spec|
        spec.name = "open_blog"
        spec.version = "0.1.0"
        spec.authors = ["Example"]
        spec.summary = "An example package"
        spec.files = ["lib/open_blog/version.rb"]
      end
    SPEC
    @env["SOURCE_DATE_EPOCH"] = git("show", "-s", "--format=%ct", "HEAD").strip
    responses = [ [ 404, "missing" ] ]
    gate = OpenBlogRelease.new(env: @env, directory: @directory, command: method(:command), http: ->(_url) { responses.shift || raise("Unexpected HTTP") })
    gate.artifact!
    assert_includes File.read(@env["GITHUB_OUTPUT"]), "should_publish=true"
    artifact = File.binread(File.join(@directory, "open_blog-0.1.0.gem"))
    responses.replace([ [ 200, '{"version":"0.1.0","platform":"ruby"}' ], [ 200, artifact ] ])
    gate.artifact!
    assert_includes File.read(@env["GITHUB_OUTPUT"]), "should_publish=false"
    [ [ [ 200, '{"version":"0.1.0","platform":"ruby"}' ], [ 200, "different" ] ],
      [ [ 503, "down" ] ], [ [ 200, "invalid JSON" ] ],
      [ [ 200, '{"version":"0.1.0","platform":"ruby"}' ], [ 404, "missing" ] ] ].each do |sequence|
      responses.replace(sequence)
      assert_raises(OpenBlogRelease::Refusal) { gate.artifact! }
    end
  end

  def test_finish_only_tags_verified_published_bytes_and_preserves_matching_annotated_tags
    File.write(File.join(@directory, "open_blog-0.1.0.gem"), "artifact")
    File.write(File.join(@directory, "open-blog-release-notes.md"), "- Ship the reader.\n")
    remote = File.join(@directory, "remote.git")
    git("init", "--bare", "-q", remote)
    git("remote", "add", "origin", remote)
    responses = []
    gate = OpenBlogRelease.new(env: @env, directory: @directory, command: method(:command), http: ->(_url) { responses.shift || raise("Unexpected HTTP") })
    responses.replace([ [ 404, "missing" ] ])
    assert_raises(OpenBlogRelease::Refusal) { gate.finish! }
    assert_empty git("tag", "--list")
    refute @commands.any? { |args| args[0, 3] == [ "gh", "release", "create" ] }
    @tags = [ { "ref" => "refs/tags/v0.1.0", "object" => { "type" => "tag", "sha" => "e" * 40 } } ]
    @tag_object = { "type" => "commit", "sha" => "f" * 40 }
    responses.replace([ [ 200, '{"version":"0.1.0","platform":"ruby"}' ], [ 200, "artifact" ] ])
    assert_raises(OpenBlogRelease::Refusal) { gate.finish! }
    assert_empty git("tag", "--list")
    @tag_object["sha"] = @main
    responses.replace([ [ 200, '{"version":"0.1.0","platform":"ruby"}' ], [ 200, "artifact" ] ])
    gate.finish!
    assert_empty git("tag", "--list")
    assert @commands.any? { |args| args[0, 3] == [ "gh", "release", "create" ] && args.include?("--verify-tag") }
    @tags = []
    responses.replace([ [ 200, '{"version":"0.1.0","platform":"ruby"}' ], [ 200, "artifact" ] ])
    gate.finish!
    assert_equal @main, git("rev-parse", "v0.1.0^{commit}").strip
    assert_includes git("ls-remote", "origin", "refs/tags/v0.1.0^{}"), @main
    push = @commands.index { |args| args[0, 3] == [ "git", "push", "origin" ] }
    release = @commands.rindex { |args| args[0, 3] == [ "gh", "release", "create" ] }
    assert_operator push, :<, release
    @tags = [ { "ref" => "refs/tags/v0.1.0", "object" => { "type" => "commit", "sha" => @main } } ]
    @releases = [ { "tag_name" => "v0.1.0", "body" => "- Ship the reader.\n", "name" => "open_blog v0.1.0", "draft" => false, "prerelease" => false } ]
    @commands.clear
    responses.replace([ [ 200, '{"version":"0.1.0","platform":"ruby"}' ], [ 200, "artifact" ] ])
    gate.finish!
    refute @commands.any? { |args| args[0, 3] == [ "git", "push", "origin" ] || args[0, 3] == [ "gh", "release", "create" ] }
    refute @commands.any? { |args| args[0, 3] == [ "gh", "release", "edit" ] }
    { "body" => "Old notes", "draft" => true, "prerelease" => true, "name" => "Old title" }.each do |field, value|
      original = @releases.first[field]
      @releases.first[field] = value
      @commands.clear
      responses.replace([ [ 200, '{"version":"0.1.0","platform":"ruby"}' ], [ 200, "artifact" ] ])
      gate.finish!
      edit = @commands.find { |args| args[0, 3] == [ "gh", "release", "edit" ] }
      assert_includes edit, "--notes-file"
      assert_includes edit, "--draft=false"
      assert_includes edit, "--prerelease=false"
      assert_includes edit, "open_blog v0.1.0"
      @releases.first[field] = original
    end
  end

  def test_workflow_only_dispatches_and_gates_before_credentials_and_publication
    workflow = YAML.load_file(File.expand_path("../.github/workflows/publish.yml", __dir__))
    assert_equal [ "workflow_dispatch" ], (workflow["on"] || workflow[true]).keys
    inputs = (workflow["on"] || workflow[true]).fetch("workflow_dispatch").fetch("inputs")
    assert inputs.fetch("version").fetch("required")
    assert inputs.fetch("sha").fetch("required")
    job = workflow.fetch("jobs").fetch("publish")
    assert_equal "release", job.fetch("environment")
    assert_includes job.fetch("if"), "github.repository == 'techwright-lab/open-blog'"
    assert_equal "write", job.fetch("permissions").fetch("id-token")
    refute workflow.fetch("permissions", {}).key?("id-token")
    assert_equal false, workflow.fetch("concurrency").fetch("cancel-in-progress")
    steps = job.fetch("steps")
    credentials = steps.index { |step| step.fetch("uses", "").start_with?("rubygems/configure-rubygems-credentials@") }
    assert_equal "rubygems/configure-rubygems-credentials@dc5a8d8553e6ee01fc26761a49e99e733d17954a", steps[credentials]["uses"]
    %w[verify artifact].each do |mode|
      assert_operator steps.index { |step| step.fetch("run", "").include?("ruby bin/release-check #{mode}") }, :<, credentials
    end
    push = steps.index { |step| step.fetch("run", "").include?("gem push") }
    finish = steps.index { |step| step.fetch("run", "").include?("ruby bin/release-check finish") }
    assert_equal "steps.artifact.outputs.should_publish == 'true'", steps[credentials]["if"]
    assert_equal steps[credentials]["if"], steps[push]["if"]
    assert_operator credentials, :<, push
    assert_operator push, :<, finish
  end

  private

  def workflow_run(workflow)
    { "id" => 1, "head_sha" => @main, "event" => "push", "head_branch" => "main",
      "head_repository" => { "full_name" => "techwright-lab/open-blog" }, "path" => ".github/workflows/#{workflow}",
      "status" => "completed", "conclusion" => "success" }
  end

  def amend_notes
    git("add", "CHANGELOG.md")
    git("commit", "--amend", "--no-edit", "-q")
    sync_evidence
  end

  def sync_evidence
    @env["RELEASE_SHA"] = @main = git("rev-parse", "HEAD").strip
    @runs = %w[ci.yml installer.yml docs.yml].to_h { |workflow| [ workflow, [ workflow_run(workflow) ] ] }
  end

  def commit_version(version)
    File.write(File.join(@directory, "lib/open_blog/version.rb"), "module OpenBlog\n  VERSION = \"#{version}\"\nend\n")
    File.write(File.join(@directory, "CHANGELOG.md"), "## [0.1.0] - 2026-01-01\n- Ship the reader.\n")
    git("add", ".")
    git("commit", "-qm", "Version #{version}", "--allow-empty")
  end

  def git(*args)
    execute("git", *args)
  end

  def execute(*args)
    stdout, stderr, status = Open3.capture3(*args, chdir: @directory)
    raise stderr unless status.success?
    stdout
  end

  def command(*args)
    @commands << args
    return execute(*args) unless args.first == "gh"
    return "" if args[0, 2] == [ "gh", "release" ]
    endpoint = args.fetch(2)
    case endpoint
    when /commits\/main$/ then JSON.generate("sha" => @main)
    when /workflows\/(.+)\/runs\?/ then JSON.generate([ { "workflow_runs" => @runs.fetch(Regexp.last_match(1)) } ])
    when /matching-refs/ then JSON.generate(@tags)
    when /git\/tags\// then JSON.generate("object" => @tag_object)
    when /releases\?/ then JSON.generate([ @releases ])
    else raise "Unexpected command: #{args.inspect}"
    end
  end
end
