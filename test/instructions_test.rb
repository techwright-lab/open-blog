require_relative "test_helper"
require "yaml"

class InstructionsTest < ActiveSupport::TestCase
  test "publishing guidance binds approval to the content and preserves unanswered facts" do
    text = OpenBlog::APPROVAL_INSTRUCTION
    assert_includes text, "revision_identifier"
    assert_includes text, "facts_checked"
    assert_includes text, "preview link"
    assert_includes text, "changes after approval"
    assert_includes OpenBlog::PROVENANCE_INSTRUCTION, "ai_assisted"
    assert_includes OpenBlog::PROVENANCE_INSTRUCTION, "human_written"
  end

  test "packaged workflows share the publication and adoption instructions" do
    root = OpenBlog::Engine.root
    names = %w[install publish update adopt policy-pages report].map { |name| "open-blog-#{name}" }
    names.each do |name|
      path = root.join("skills", name, "SKILL.md")
      assert path.file?, "Missing workflow #{name}"
      text = path.read
      header = YAML.safe_load(text.split("---", 3).fetch(1))
      assert_equal name, header.fetch("name")
      assert header.fetch("description").present?
      assert_match(/blog_\w+|open_blog:doctor/, text)
    end
    %w[publish update].each do |name|
      assert_includes root.join("skills/open-blog-#{name}/SKILL.md").read, OpenBlog::APPROVAL_INSTRUCTION
    end
    assert_includes root.join("skills/open-blog-adopt/SKILL.md").read, OpenBlog::ADOPTION_INSTRUCTION
    assert_includes root.join("docs/publishing.md").read, OpenBlog::APPROVAL_INSTRUCTION
    assert_includes root.join("docs/adoption.md").read, OpenBlog::ADOPTION_INSTRUCTION
  end
end
