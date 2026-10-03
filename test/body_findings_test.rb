require_relative "test_helper"
require "minitest/mock"

class BodyFindingsTest < ActiveSupport::TestCase
  setup do
    @origin = OpenBlog.config.public_base_url
    OpenBlog.config.public_base_url = "https://garden.example"
  end

  teardown do
    OpenBlog.config.public_base_url = @origin
  end

  test "heading checks inspect source levels before normalization" do
    post = markdown("# Watering\n\n### Containers\n")
    findings = body_findings(post)
    assert_equal %i[heading_level_skipped heading_h1_in_body], findings.pluck(:code)
    assert_equal "body.headings[1]", findings.find { |finding| finding[:code] == :heading_level_skipped }[:location]
    assert_equal "body.headings[0]", findings.find { |finding| finding[:code] == :heading_h1_in_body }[:location]
    assert_equal [], body_findings(markdown("## Watering\n\n### Containers\n\n## Soil\n"))
    assert_equal [], body_findings(markdown("#### The only heading\n"))
  end

  test "rich text source headings use the same checks" do
    post = OpenBlog::Post.new(body_format: "rich_text")
    post.rich_body = "<h1>Watering</h1><h3>Containers</h3>"
    assert_equal %i[heading_level_skipped heading_h1_in_body], body_findings(post).pluck(:code)
  end

  test "raw HTML and fenced headings in Markdown do not generate findings" do
    post = markdown("<h1>Hidden input</h1>\n\n```markdown\n# Example\n### Example detail\n```\n")
    assert_empty body_findings(post)
  end

  test "body and cover images without meaningful alternative text are reported" do
    post = markdown("![](https://garden.example/leaf.png)")
    finding = body_findings(post).find { |entry| entry[:code] == :image_alt_absent }
    assert_equal "body.images[0].alt", finding[:location]
    post.body_markdown = "![A green leaf](https://garden.example/leaf.png)"
    assert_empty body_findings(post)
    post.cover_image = OpenBlog::Image.new(sha256: "c" * 64, filename: "cover.png", content_type: "image/png", byte_size: 1)
    post.cover_alt = "  "
    assert_equal "cover_alt", body_findings(post).sole[:location]
    post.cover_alt = "A raised garden bed"
    assert_empty body_findings(post)
  end

  test "only images on another host are external including protocol-relative URLs" do
    post = markdown("![Leaf](/images/leaf.png)\n\n![Leaf](https://garden.example/leaf.png)\n\n![Leaf](https://cdn.example/leaf.png)")
    finding = body_findings(post).sole
    assert_equal :image_external, finding[:code]
    assert_equal "body.images[2]", finding[:location]
    post.body_markdown = "![Leaf](//cdn.example/leaf.png)"
    assert_equal :image_external, body_findings(post).sole[:code]
    post.body_markdown = "![Leaf](https://GARDEN.example/leaf.png)"
    assert_empty body_findings(post)
    OpenBlog.config.public_base_url = nil
    assert_equal :image_external, body_findings(post).sole[:code]
  end

  test "one findings call inspects the document once and later calls see edits" do
    post = markdown("# First heading\n")
    count = 0
    original = OpenBlog::Renderer.method(:document)
    OpenBlog::Renderer.stub(:document, ->(value) { count += 1; original.call(value) }) do
      assert_includes OpenBlog::Findings.for(post).pluck(:code), :heading_h1_in_body
      assert_equal 1, count
      post.body_markdown = "Ordinary prose."
      refute_includes OpenBlog::Findings.for(post).pluck(:code), :heading_h1_in_body
      assert_equal 2, count
    end
  end

  private

  def markdown(body)
    OpenBlog::Post.new(title: "Garden notes", body_format: "markdown", body_markdown: body)
  end

  def body_findings(post)
    context = {}
    OpenBlog::Findings::BodyChecks.build.flat_map { |check| check.call(post, context: context) }
  end
end
