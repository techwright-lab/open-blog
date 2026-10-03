require_relative "test_helper"

class FaqReaderTest < ActionDispatch::IntegrationTest
  setup do
    @entries = [
      { question: "Which pot & soil?", answer: "Use a wide pot.\r\n\r\nKeep drainage clear.\r\nhttps://garden.example/pots?a=1&b=2" },
      { question: "Is <strong>shade</strong> useful?", answer: "**Light** shade helps. <script>alert('leaf')</script> remains text." },
      { question: "How much water?", answer: "Check the soil first.\nAdd water slowly." }
    ]
    @result = OpenBlog::Publish.call({ title: "A container guide", slug: "container-guide",
      description: "A few answers for new gardeners.", body: "## Getting started\n\nPrepare a pot.\n\n## FAQ\n\n### A body question?\n\nA separate body answer.",
      faq: @entries }, actor: "Garden editor", now: 2.days.ago)
    @post = @result.post
    @post.publications.create!(revision: @post.public_revision, entry_type: "correction", occurred_at: 1.day.ago, note: "Clarified pot size.")
  end

  test "FAQ records retain order and text across the page schema and revision" do
    get @post.path
    assert_response :success
    document = Nokogiri::HTML5(response.body)
    section = document.at_css("article[data-open-blog-content] > [data-open-blog-faq]")
    assert section
    assert_equal 1, document.css("[data-open-blog-faq]").length
    nodes = section.css("[data-open-blog-faq-entry]")
    assert_equal 3, nodes.length
    payload = JSON.parse(@post.reload.public_revision.payload).fetch("faq")
    actual = nodes.map do |node|
      { "question" => normalize(node.at_css("h3").text),
        "answer" => normalize(node.css("p").map { |paragraph| paragraph.inner_html.gsub(/<br\s*\/?>/, " ") }.map { |html| Nokogiri::HTML5.fragment(html).text }.join(" ")) }
    end
    assert_equal payload.map { |row| row.transform_values { |text| normalize(text) } }, actual
    graph = JSON.parse(document.at_css("script[type='application/ld+json']").text).fetch("@graph")
    questions = graph.select { |item| item["@type"] == "FAQPage" }.sole.fetch("mainEntity")
    assert_equal @entries.map { |row| row[:question] }, questions.map { |row| row.fetch("name") }
    assert_equal @entries.map { |row| row[:answer] }, questions.map { |row| row.fetch("acceptedAnswer").fetch("text") }
    assert_equal 2, nodes.first.css("p").length
    assert_equal 1, nodes.first.css("br").length
    assert_equal "https://garden.example/pots?a=1&b=2", nodes.first.at_css("a")["href"]
    assert_empty section.css("script, strong")
    children = section.parent.element_children.to_a
    assert_operator children.index(section), :>, children.index(document.at_css("[data-open-blog-body]"))
    assert_operator children.index(section), :>, children.index(document.at_css(".ob-correction"))
    assert_equal 1, document.css(".ob-toc a[href='##{section.at_css('h2')['id']}']").length
  end

  test "FAQ records remain searchable and body FAQ findings remain distinct" do
    @entries.each do |entry|
      assert_includes @post.reload.search_text, entry[:question]
      assert_includes @post.search_text, entry[:answer]
    end
    codes = OpenBlog::Findings.for(@post).pluck(:code)
    assert_includes codes, :faq_in_body
    assert_includes codes, :faq_markup_in_answer
    get @post.path
    assert_response :success
    assert_select "[data-open-blog-body] h2", text: /FAQ/, count: 1
    assert_select "[data-open-blog-faq] > h2", text: "Frequently asked questions", count: 1
  end

  test "a post without FAQ records has no reader section or FAQ schema" do
    @post = OpenBlog::Publish.call({ faq: [], change: "substantive" }, post: @post, actor: "Garden editor").post
    get @post.path
    assert_response :success
    assert_select "[data-open-blog-faq]", count: 0
    graph = JSON.parse(Nokogiri::HTML5(response.body).at_css("script[type='application/ld+json']").text).fetch("@graph")
    refute graph.any? { |item| item["@type"] == "FAQPage" }
    assert_includes OpenBlog::Findings.for(@post).pluck(:code), :faq_in_body
  end

  private

  def normalize(value)
    value.unicode_normalize(:nfc).gsub(/[[:space:]]+/, " ").strip
  end
end
