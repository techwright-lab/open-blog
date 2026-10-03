require_relative "test_helper"

class RendererReviewTest < ActiveSupport::TestCase
  test "markup nested in a code block cannot crash rendering or invent payload images" do
    post = OpenBlog::Post.new(body_format: "rich_text")
    post.rich_body = '<pre lang="ruby"><code><img src="https://cdn.example/leaf.png" alt="leaf">puts 1</code></pre>'
    html = OpenBlog::Renderer.render_string(post.body_for_payload, format: "rich_text", post: post)
    fragment = Nokogiri::HTML5.fragment(html)
    assert_empty fragment.css("img")
    assert_equal "puts 1", fragment.at_css("pre > code").text
    assert_empty OpenBlog::ImageResolution.body_images(post)
    assert_empty OpenBlog::Renderer.document(post).css("img")
  end

  test "cached HTML changes when rendering configuration changes" do
    original_cache = Rails.cache
    original_breaks = OpenBlog.config.markdown_hardbreaks
    original_origin = OpenBlog.config.public_base_url
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    author = OpenBlog::Author.create!(name: "Cache Reviewer", slug: "cache-reviewer")
    post = OpenBlog::Post.create!(title: "Cached garden notes", slug: "cached-garden-notes", author: author, author_name: author.name,
      body_markdown: "First line.\nSecond line.\n\n[Visit](https://garden.example/notes)")
    identifier = post.current_revision_identifier
    OpenBlog.config.markdown_hardbreaks = true
    OpenBlog.config.public_base_url = "https://garden.example"
    first = Nokogiri::HTML5.fragment(OpenBlog::Renderer.render(post))
    assert first.at_css("br")
    refute first.at_css("a")["rel"].to_s.split.include?("noopener")
    OpenBlog.config.markdown_hardbreaks = false
    second = Nokogiri::HTML5.fragment(OpenBlog::Renderer.render(post))
    assert_nil second.at_css("br")
    refute second.at_css("a")["rel"].to_s.split.include?("noopener")
    OpenBlog.config.public_base_url = "https://other.example"
    third = Nokogiri::HTML5.fragment(OpenBlog::Renderer.render(post))
    assert_includes third.at_css("a")["rel"].to_s.split, "noopener"
    assert_equal identifier, post.current_revision_identifier
  ensure
    Rails.cache = original_cache
    OpenBlog.config.markdown_hardbreaks = original_breaks
    OpenBlog.config.public_base_url = original_origin
  end
end
