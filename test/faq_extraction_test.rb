require_relative "test_helper"

class FaqExtractionTest < ActiveSupport::TestCase
  test "a body without a matching heading is returned byte for byte" do
    body = fixture("none")
    result = extract(body)
    assert_equal "none", result[:class]
    assert_equal body, result[:body_after]
    assert_equal [], result[:pairs]
    assert_equal [], result[:cut]
    assert_equal [], result[:leftover]
    assert_equal [], result[:reasons]
    assert_equal Digest::SHA256.hexdigest(body), result[:source_body_sha256]
  end

  test "heading questions at the end yield four pairs and a clean body" do
    body = fixture("clean_end")
    result = extract(body)
    assert_equal "clean", result[:class]
    assert_equal 4, result[:pairs].length
    assert_equal({ question: "When should I water?", answer: "When the topsoil feels dry." }, result[:pairs].first)
    assert_equal "# Growing basil\n\nKeep the pot by a window.\n", result[:body_after]
    assert_equal [ { start: body.index("## FAQ"), end: body.bytesize } ], result[:cut]
    assert_empty result[:leftover]
    assert_empty result[:reasons]
    assert_equal "none", extract(result[:body_after])[:class]
  end

  test "a middle section preserves surrounding bytes with byte offsets" do
    body = fixture("clean_middle")
    result = extract(body)
    assert_equal "clean", result[:class]
    assert_equal [ { question: "Where can mint grow?", answer: "In a roomy container." } ], result[:pairs]
    start = body.b.index("## Common")
    finish = body.b.index("## Closing")
    assert_equal [ { start: start, end: finish } ], result[:cut]
    assert_equal "Préface 🌿.\n\n## Closing notes\n\nKeep this spacing.  \n", result[:body_after]
    assert_equal body.byteslice(start...finish), body.b.byteslice(result[:cut].first[:start]...result[:cut].first[:end]).force_encoding("UTF-8")
    assert_equal "none", extract(result[:body_after])[:class]
  end

  test "bold questions can have answers on the same or following line" do
    result = extract(fixture("clean_bold"))
    assert_equal "clean", result[:class]
    assert_equal [ { question: "Do seedlings need warmth?", answer: "Yes, steady warmth helps." },
      { question: "When do roots appear?", answer: "After the seed opens." } ], result[:pairs]
    assert_equal "Opening.\n", result[:body_after]
  end

  test "plain answer paragraphs and line breaks are retained" do
    result = extract(fixture("plain_paragraphs"))
    assert_equal "clean", result[:class]
    assert_equal "Use a dry jar.\nLabel it clearly.\n\nKeep the jar in a cool place.", result[:pairs].sole[:answer]
  end

  test "each ambiguous shape has a stable review reason" do
    {
      "leftover" => "leftover_text", "question_mark" => "question_without_question_mark",
      "duplicate_question" => "duplicate_question", "heading_answer" => "heading_in_answer",
      "duplicate_heading" => "multiple_faq_headings", "fenced_heading" => "faq_heading_in_code",
      "markdown_loss" => "markdown_in_answer", "bold_multiline" => "multiline_bold_answer"
    }.each do |name, reason|
      result = extract(fixture(name))
      assert_equal "review", result[:class], name
      assert_includes result[:reasons], reason, name
    end
    assert_equal [ "These answers were gathered yesterday." ], extract(fixture("leftover"))[:leftover]
    result = extract(fixture("markdown_loss"))
    assert_equal "A small pot\nFresh soil", result[:pairs].sole[:answer]
    result = extract(fixture("fenced_heading"))
    assert_empty result[:cut]
    assert_equal fixture("fenced_heading"), result[:body_after]
  end

  test "standalone sections use disjoint byte ranges and leave intervening prose intact" do
    body = fixture("standalone")
    result = extract(body, standalone_questions: [ "Is the pot ready?", "Should I add water?" ])
    assert_equal "review", result[:class]
    assert_equal [ "standalone_question" ], result[:reasons]
    assert_equal [ { question: "Is the pot ready?", answer: "Yes, it is clean." },
      { question: "Should I add water?", answer: "Add a little." } ], result[:pairs]
    assert_equal [ { start: body.b.index("## Is the"), end: body.b.index("## Notes") },
      { start: body.b.index("## Should"), end: body.b.index("## Closing") } ], result[:cut]
    assert_equal "Opening 🌱.\n\n## Notes to keep\n\nLeave this paragraph exactly as written.\n\n## Closing\n\nThis stays too.\n", result[:body_after]
    assert_equal "none", extract(result[:body_after], standalone_questions: [ "Is the pot ready?", "Should I add water?" ])[:class]
  end

  test "heading matching is limited to the supported levels and word boundaries" do
    [ "FAQ", "Our FAQ details", "Frequently asked questions about herbs", "COMMON QUESTIONS", "Q&A today" ].each do |heading|
      assert OpenBlog::FaqExtraction.faq_heading?(heading)
      assert OpenBlog::FaqExtraction.contains_faq_heading?("### #{heading}\n")
    end
    refute OpenBlog::FaqExtraction.faq_heading?("FAQuestions")
    refute OpenBlog::FaqExtraction.contains_faq_heading?("# FAQ\n")
    refute OpenBlog::FaqExtraction.contains_faq_heading?("#### FAQ\n")
  end

  test "raw CRLF bytes are hashed and outside-section line endings stay unchanged" do
    body = "Opening.\r\n\r\n## FAQ\r\n\r\n### Ready?\r\nYes.\r\n\r\n## Next\r\nUnchanged.\r\n"
    result = extract(body)
    assert_equal Digest::SHA256.hexdigest(body), result[:source_body_sha256]
    assert_equal "Opening.\n\n## Next\r\nUnchanged.\r\n", result[:body_after]
    assert_equal "clean", result[:class]
  end

  test "adjacent standalone cuts do not consume the following section" do
    body = "Opening.\n\n## First?\nOne.  \n\n\n## Second?\nTwo.\n\n## Retained\nUnchanged words.\n"
    result = extract(body, standalone_questions: [ "First?", "Second?" ])
    assert_equal "Opening.\n\n## Retained\nUnchanged words.\n", result[:body_after]
    assert_equal [ { start: body.b.index("## First"), end: body.b.index("## Retained") } ], result[:cut]
  end

  test "entities and escapes that change text require review while bare URLs stay plain" do
    result = extract("## FAQ\n\n### Ready?\nUse A &amp; B.\n")
    assert_equal "review", result[:class]
    assert_includes result[:reasons], "markdown_in_answer"
    assert_equal "Use A & B.", result[:pairs].sole[:answer]
    plain = extract("## FAQ\n\n### Where?\nVisit https://garden.example for details.\n")
    assert_equal "clean", plain[:class]
    assert_equal "Visit https://garden.example for details.", plain[:pairs].sole[:answer]
  end

  test "literal trailing hashes are retained and Markdown closing hashes require whitespace" do
    result = extract("## C#\nA programming language.\n", standalone_questions: [ "C#" ])
    assert_equal [ { question: "C#", answer: "A programming language." } ], result[:pairs]
    assert_equal "review", result[:class]
    closing = extract("## FAQ ##\n\n### Is it ready? ###\nYes.\n")
    assert_equal "clean", closing[:class]
    assert_equal "Is it ready?", closing[:pairs].sole[:question]
  end

  test "question markup is converted to plain text and requires review" do
    result = extract("## FAQ\n\n### What is **loam**?\nA soil mixture.\n")
    assert_equal "What is loam?", result[:pairs].sole[:question]
    assert_equal "review", result[:class]
    assert_includes result[:reasons], "markdown_in_question"
    bold = extract("## FAQ\n\n**Can _mint_ grow here?** Yes.\n")
    assert_equal "Can mint grow here?", bold[:pairs].sole[:question]
    assert_includes bold[:reasons], "markdown_in_question"
  end

  private

  def fixture(name)
    File.binread(File.expand_path("fixtures/faq_bodies/#{name}.md", __dir__)).force_encoding("UTF-8")
  end

  def extract(body, **options)
    OpenBlog::FaqExtraction.call(body: body, **options)
  end
end
