require_relative "test_helper"
require "minitest/mock"

class FaqHelperTest < ActiveSupport::TestCase
  setup do
    @view = ActionView::Base.empty
    @view.extend(OpenBlog::UrlHelper)
    @view.extend(OpenBlog::ContentHelper)
    @view.extend(OpenBlog::FaqHelper)
    @post = OpenBlog::Post.new(body_markdown: "## Soil\n\nCare.\n\n## Water\n\nOften.")
    @collapsed = OpenBlog.config.faq_collapsed
  end

  teardown { OpenBlog.config.faq_collapsed = @collapsed }

  test "an empty FAQ renders no section" do
    assert_equal "", @view.open_blog_faq(@post)
    assert_equal "", @view.open_blog_toc(@post)
  end

  test "FAQ uses loaded candidate order and excludes destroyed records" do
    @post.faqs.build(question: "Later?", answer: "Last answer.", position: 3)
    @post.faqs.build(question: "First?", answer: "First answer.", position: 1)
    removed = @post.faqs.build(question: "Removed?", answer: "Never shown.", position: 2)
    removed.mark_for_destruction
    @post.faqs.build(question: "Middle?", answer: "Middle answer.", position: 2)
    doc = faq
    assert_equal 1, doc.css(OpenBlog::FAQ_SELECTORS.fetch(:section)).length
    entries = doc.css(OpenBlog::FAQ_SELECTORS.fetch(:entry))
    assert_equal [ "First?", "Middle?", "Later?" ], entries.map { |entry| entry.at_css("h3").text }
    assert_equal [ "First answer.", "Middle answer.", "Last answer." ], entries.map { |entry| entry.at_css("p").text }
    assert_equal "Frequently asked questions", doc.at_css("section > h2").text
    assert_empty doc.css("button, [hidden]")
  end

  test "entries are closed disclosures whose summary holds the question heading" do
    @post.faqs.build(question: "How <b>often</b>?", answer: "Each week.\n\nMore in summer.", position: 1)
    @post.faqs.build(question: "Where?", answer: "By a window.", position: 2)
    doc = faq
    entries = doc.css("section.ob-faq > details.ob-faq-entry[data-open-blog-faq-entry]")
    assert_equal 2, entries.length
    assert_empty doc.css("details[open], div.ob-faq-entry")
    entries.each { |entry| assert_equal %w[summary p], entry.element_children.map(&:name).uniq }
    assert_equal [ "How <b>often</b>?", "Where?" ], entries.map { |entry| entry.at_css("summary > h3:only-child").text }
    assert_equal [ "Each week.", "More in summer." ], entries.first.css("> p").map(&:text)
    assert_equal "open-blog-faq", doc.at_css("section > h2")["id"]
  end

  test "the expanded markup is kept when collapsing is turned off" do
    OpenBlog.config.faq_collapsed = false
    @post.faqs.build(question: "How often?", answer: "Each week.\n\nMore in summer.", position: 1)
    doc = faq
    entry = doc.css("section.ob-faq > div.ob-faq-entry[data-open-blog-faq-entry]").sole
    assert_equal %w[h3 p p], entry.element_children.map(&:name)
    assert_equal "How often?", entry.at_css("> h3").text
    assert_empty doc.css("details, summary, button, [hidden]")
  end

  test "plain text preserves literal markup paragraphs line breaks and safe visible URL characters" do
    question = '<script>Question & "quote"?</script>'
    answer = "**bold** <em>plain</em> & words\r\n\r\nLine one\r\nhttps://example.com/path?a=1&b=2. Then (https://example.com/wiki/Tree_(plant)).\njavascript:alert(1) ftp://example.com/file"
    @post.faqs.build(question: question, answer: answer, position: 1)
    doc = faq
    assert_equal question, doc.at_css("h3").text
    assert_empty doc.css("script, em, strong")
    assert_equal 2, doc.css("p").length
    assert_equal 2, doc.css("br").length
    assert_equal [ "https://example.com/path?a=1&b=2", "https://example.com/wiki/Tree_(plant)" ], doc.css("a").map { |link| link["href"] }
    assert_equal [ "https://example.com/path?a=1&b=2", "https://example.com/wiki/Tree_(plant)" ], doc.css("a").map(&:text)
    assert_equal normalize(answer), normalize(doc.css("p").map(&:text).join("\n"))
  end

  test "trusted strings are still escaped as plain FAQ text" do
    @post.faqs.build(question: "<b>Question</b>".html_safe, answer: "<img src=x onerror=bad()>".html_safe, position: 1)
    doc = faq
    assert_empty doc.css("b, img")
    assert_equal "<b>Question</b>", doc.at_css("h3").text
    assert_equal "<img src=x onerror=bad()>", doc.at_css("p").text
  end

  test "FAQ contributes one section toward the TOC threshold and avoids all rendered IDs" do
    @post.faqs.build(question: "How?", answer: "Carefully.", position: 1)
    @post.faqs.build(question: "When?", answer: "Today.", position: 2)
    rendered = '<h2 id="soil">Soil</h2><h3 id="water">Water</h3><div id="open-blog-faq"></div><span id="open-blog-faq-1"></span>'
    OpenBlog::Renderer.stub(:render, rendered) do
      identifier = faq.at_css("section > h2")["id"]
      assert_equal "open-blog-faq-2", identifier
      toc = Nokogiri::HTML5.fragment(@view.open_blog_toc(@post))
      assert_equal [ "#soil", "#water", "##{identifier}" ], toc.css("a").map { |node| node["href"] }
      assert_equal "Frequently asked questions", toc.css("a").last.text
    end
    @post.body_markdown = "## One heading"
    assert_equal "", @view.open_blog_toc(@post)
  end

  test "a body FAQ and record FAQ remain distinct" do
    @post.body_markdown = "## Open blog FAQ\n\nBody questions.\n\n## Care\n\nKeep watering."
    @post.faqs.build(question: "Where?", answer: "By a window.", position: 1)
    assert_equal "open-blog-faq-1", faq.at_css("h2")["id"]
    toc = Nokogiri::HTML5.fragment(@view.open_blog_toc(@post))
    assert_equal [ "#open-blog-faq", "#care", "#open-blog-faq-1" ], toc.css("a").map { |node| node["href"] }
  end

  private

  def faq
    Nokogiri::HTML5.fragment(@view.open_blog_faq(@post))
  end

  def normalize(text)
    text.gsub(/\s+/, " ").strip
  end
end
