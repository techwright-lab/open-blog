require_relative "test_helper"

class FaqOutputsTest < ActiveSupport::TestCase
  setup do
    @original = OpenBlog.config
    OpenBlog.instance_variable_set(:@config, OpenBlog::Configuration.new)
    OpenBlog.configure do |config|
      config.site_name = "Field Notes"
      config.public_base_url = "https://notes.example"
      config.default_author = { name: "Alex Green", type: :person }
      config.publisher = { name: "Field Notes", url: "https://notes.example" }
    end
    @now = Time.utc(2026, 9, 10, 12)
    @post = OpenBlog::Publish.call({ title: "Growing trees", slug: "growing-trees", description: "Care for trees.",
      body: "## Soil\n\nKeep **this** Markdown.", provenance: "human_written",
      faq: [ { question: "First?", answer: "One." }, { question: "Second?", answer: "Two." } ] }, actor: "Editor", now: @now - 2.days).post
    @view = ActionView::Base.empty
    [ OpenBlog::UrlHelper, OpenBlog::HeadHelper, OpenBlog::StructuredDataHelper ].each { |helper| @view.extend(helper) }
  end

  teardown do
    OpenBlog.instance_variable_set(:@config, @original)
  end

  test "FAQ JSON preserves stored bytes and loaded candidate order without a script breakout" do
    escape = ActiveSupport::JSON::Encoding.escape_html_entities_in_json
    ActiveSupport::JSON::Encoding.escape_html_entities_in_json = false
    @post.faqs.load
    @post.faqs.first.mark_for_destruction
    @post.faqs.last.position = 4
    answer = " **yes** & <b>literal</b>\r\n\r\n</script><script>bad()</script> "
    @post.faqs.build(position: 3, question: " <em>New?</em> ", answer: answer)
    doc = Nokogiri::HTML5.fragment(@view.open_blog_structured_data(@post))
    assert_equal 1, doc.css("script").length
    graph = JSON.parse(doc.at_css("script").text).fetch("@graph")
    faq = graph.select { |entry| entry["@type"] == "FAQPage" }.sole
    assert_equal [ " <em>New?</em> ", "Second?" ], faq.fetch("mainEntity").map { |entry| entry["name"] }
    assert_equal answer, faq["mainEntity"].first.dig("acceptedAnswer", "text")
    assert_equal [ "Question", "Question" ], faq["mainEntity"].map { |entry| entry["@type"] }
    assert_equal [ "Answer", "Answer" ], faq["mainEntity"].map { |entry| entry.dig("acceptedAnswer", "@type") }
    assert_equal 1, graph.count { |entry| entry["@type"] == "BlogPosting" }
  ensure
    ActiveSupport::JSON::Encoding.escape_html_entities_in_json = escape
  end

  test "FAQ JSON is omitted when all rows are removed and on list pages" do
    @post.faqs.each(&:mark_for_destruction)
    [ @post, OpenBlog::ReaderPage.new(kind: :index, path: "/blog", base_url: "https://notes.example") ].each do |resource|
      graph = JSON.parse(Nokogiri::HTML5.fragment(@view.open_blog_structured_data(resource)).at_css("script").text).fetch("@graph")
      refute graph.any? { |entry| entry["@type"] == "FAQPage" }
    end
  end

  test "Markdown output preserves the raw body and orders visible metadata FAQ and canonical" do
    @post.modified_at = @now - 1.day
    output = OpenBlog::MarkdownView.render(@post, now: @now)
    sections = [ "# Growing trees", "Care for trees.", "Alex Green", "Published", "Updated", @post.body_markdown,
      "## Frequently asked questions", "### First?", "One.", "### Second?", "Two.", "https://notes.example/blog/growing-trees" ]
    positions = sections.map { |text| output.index(text).tap { |position| assert position, "Missing #{text.inspect} in #{output}" } }
    assert_equal positions.sort, positions
    assert output.end_with?("https://notes.example/blog/growing-trees\n")
    refute_includes output, "AI"
  end

  test "Markdown FAQ uses loaded rows and renders every stored plain character literally" do
    @post.faqs.each(&:mark_for_destruction)
    answer = "**bold** <b>literal</b> &amp; [label](javascript:bad)\n\n1. numbered\n- item\n# heading"
    @post.faqs.build(position: 9, question: "Last?", answer: "Last answer.")
    @post.faqs.build(position: 2, question: "<script>**Question?**</script>", answer: answer)
    output = OpenBlog::MarkdownView.render(@post, now: @now)
    html = Nokogiri::HTML5.fragment(Commonmarker.to_html(output))
    assert_equal [ "<script>**Question?**</script>", "Last?" ], html.css("h3").map(&:text)
    faq = output.split("## Frequently asked questions", 2).last.split("https://notes.example/blog/growing-trees", 2).first
    text = OpenBlog::PlainText.from_markdown(faq)
    assert_includes text.gsub(/\s+/, " "), answer.gsub(/\s+/, " ")
    assert_empty html.css("script, b, ol, ul")
    assert_equal [ "Growing trees" ], html.css("h1").map(&:text)
    refute_includes output, "### First?"
  end

  test "Markdown rich text is Action Text plain text without treating literal characters as markup" do
    @post.body_format = "rich_text"
    @post.rich_body = "<p>Rich <strong>words</strong> &lt;script&gt;literal&lt;/script&gt;</p><p>**plain**</p>"
    output = OpenBlog::MarkdownView.render(@post, now: @now)
    plain = OpenBlog::PlainText.from_markdown(output)
    assert_includes plain.gsub(/\s+/, " "), @post.rich_body.to_plain_text.gsub(/\s+/, " ")
    html = Nokogiri::HTML5.fragment(Commonmarker.to_html(output))
    assert_empty html.css("script, strong")
  end

  test "Markdown dates are truthful independent and never use audit timestamps" do
    @post.published_at = nil
    @post.modified_at = @now - 1.day
    @post.created_at = @now - 8.years
    output = OpenBlog::MarkdownView.render(@post, now: @now)
    refute_includes output, "Published"
    assert_includes output, "Updated"
    refute_includes output, "2018"
    @post.modified_at = @now + 1.day
    output = OpenBlog::MarkdownView.render(@post, now: @now)
    refute_includes output, "Updated"
    @post.published_at = @now + 1.day
    refute_includes OpenBlog::MarkdownView.render(@post, now: @now), "Published"
  end

  test "Markdown includes policy notices and uses latest recorded paid declaration" do
    @post.provenance = "ai_assisted"
    @post.connection_declarations.create!(declared_by: "Editor", declared_on: Date.new(2026, 9, 1), connections: [], third_party_paid: false)
    @post.connection_declarations.create!(declared_by: "Editor", declared_on: Date.new(2026, 8, 1), connections: [], third_party_paid: true)
    output = OpenBlog::MarkdownView.render(@post, now: @now)
    assert_includes output, I18n.t("open_blog.notices.ai_assisted")
    assert_includes output, I18n.t("open_blog.notices.paid")
    assert_operator output.index(I18n.t("open_blog.notices.paid")), :<, output.index(@post.body_markdown)
  end

  test "Markdown omits empty FAQ and resolves canonical and request origins" do
    @post.faqs.each(&:mark_for_destruction)
    @post.canonical_url = "https://archive.example/original"
    output = OpenBlog::MarkdownView.render(@post, now: @now)
    refute_includes output, "Frequently asked questions"
    assert output.end_with?("https://archive.example/original\n")
    @post.canonical_url = nil
    OpenBlog.config.public_base_url = nil
    assert OpenBlog::MarkdownView.render(@post, base_url: "https://host.example", now: @now).end_with?("https://host.example/blog/growing-trees\n")
  end
end
