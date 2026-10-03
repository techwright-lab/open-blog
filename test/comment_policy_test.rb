require "minitest/autorun"

class CommentPolicyTest < Minitest::Test
  def test_ruby_comment_blocks_are_at_most_three_lines
    root = File.expand_path("..", __dir__)
    files = Dir.glob("{lib,app,config,db,skills,test}/**/*.rb", base: root) + Dir.glob("{*.gemspec,Gemfile,Rakefile}", base: root)
    refute_empty files
    violations = files.flat_map do |path|
      consecutive_comments = 0
      File.foreach(File.join(root, path)).with_index(1).filter_map do |line, number|
        consecutive_comments = line.match?(/^\s*#/) ? consecutive_comments + 1 : 0
        "#{path}:#{number}: comment block exceeds three lines" if consecutive_comments == 4
      end
    end

    assert_empty violations, violations.join("\n")
  end
end
