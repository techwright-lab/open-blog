require "minitest/autorun"
require "open_blog/plain_text"

class PlainTextTest < Minitest::Test
  def test_markdown_keeps_visible_words_and_code_without_formatting_or_destinations
    markdown = <<~MARKDOWN
      # Garden **notes**

      Plant *mint* with [basil](https://example.org/herbs) and ![green leaves](/leaf.png).

      ```ruby
      puts "harvest"
      # this is code
      ```

      <div>Fresh <b>herbs</b>.</div>
    MARKDOWN
    assert_equal "Garden notes\nPlant mint with basil and green leaves.\nputs \"harvest\"\n# this is code\nFresh herbs.", OpenBlog::PlainText.from_markdown(markdown)
  end

  def test_markdown_handles_nested_formatting_reference_links_and_inline_html
    markdown = "A **strong _stem_** and [tall plant][plant], `<seed>`, <span>ready</span>.\n\n[plant]: https://example.org/plant\n"
    assert_equal "A strong stem and tall plant, <seed>, ready.", OpenBlog::PlainText.from_markdown(markdown)
  end

  def test_html_returns_fragment_text_with_entities_decoded
    assert_equal "Garden & growMint leaves", OpenBlog::PlainText.from_html("<h2>Garden &amp; grow</h2><p>Mint <em>leaves</em></p>")
  end

  def test_absent_content_is_empty
    assert_equal "", OpenBlog::PlainText.from_markdown(nil)
    assert_equal "", OpenBlog::PlainText.from_html(nil)
  end
end
