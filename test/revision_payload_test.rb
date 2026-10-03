require "minitest/autorun"
require "open_blog/revision_payload"

class RevisionPayloadTest < Minitest::Test
  def test_serialized_bytes_and_identifier
    payload = build_payload
    expected = '{"author":"Robin Vale","body":"Seeds sprout.","description":"","faq":[],"images":[],"search_description":"","search_title":"","title":"Maple journal","version":"1"}'
    assert_equal expected, payload.to_json
    assert_equal "e2fe771221edf6c68165758cb26850057772fe4be273f0661d60e95d6a5ea6a5", payload.identifier
    assert_equal Encoding::UTF_8, payload.to_json.encoding
    assert_equal "1", OpenBlog::RevisionPayload::VERSION
  end

  def test_unicode_line_ends_and_nonbody_edges_are_normalized
    payload = build_payload(title: " \tRe\u0301colte\r\n", author: " Robin Vale\t", body: "Row one\r\nRow two\r\r\n")
    assert_equal "Récolte", payload.to_h["title"]
    assert_equal "Robin Vale", payload.to_h["author"]
    assert_equal "Row one\nRow two", payload.to_h["body"]
    assert_equal build_payload(title: "Récolte", body: "Row one\nRow two").identifier, payload.identifier
  end

  def test_body_spaces_and_internal_line_breaks_are_preserved
    text = "  Leaves  \r\nRoots\t \n\n"
    assert_equal "  Leaves  \nRoots\t ", build_payload(body: text).to_h["body"]
    refute_equal build_payload(body: "Leaves\nRoots").identifier, build_payload(body: "Leaves  \nRoots").identifier
    assert_equal "\nSeeds", build_payload(body: "\nSeeds\n").to_h["body"]
  end

  def test_only_ascii_spaces_tabs_and_line_feeds_are_trimmed
    text = "\u00a0Title\u00a0"
    assert_equal text, build_payload(title: text).to_h["title"]
    assert_equal "\vTitle\f", build_payload(title: "\vTitle\f").to_h["title"]
  end

  def test_json_escape_bytes_do_not_depend_on_rails_html_escaping
    body = "A\u0000\b\t\n\f\r\"\\/<>\u2028\u2029🪴"
    payload = build_payload(body: body)
    assert_includes payload.to_json, 'A\u0000\b\t\n\f\n\"\\\\/<>'
    assert_includes payload.to_json, "\u2028\u2029🪴"
    assert_equal "b3f49e2cb73835d4c944c03744c317d5a6ebdb9fb287d7ea43d981496bf8780d", payload.identifier
  end

  def test_nil_text_becomes_empty_string
    payload = build_payload(title: nil, body: nil, author: nil)
    %w[title body author description search_title search_description].each do |key|
      assert_equal "", payload.to_h[key]
    end
  end

  def test_images_have_fixed_sorted_keys_and_keep_url_form_and_order
    images = [
      { role: "cover", url: "/notes/media/abc/seed.png", sha256: "a" * 64, alt: " Seeds \r\n" },
      { "role" => "body", "url" => "https://images.example.org/leaf.png", "sha256" => "b" * 64, "alt" => "Leaf", "width" => 300 }
    ]
    payload = build_payload(images: images)
    assert_equal %w[alt role sha256 url], payload.to_h["images"].first.keys
    assert_equal [ "/notes/media/abc/seed.png", "https://images.example.org/leaf.png" ], payload.to_h["images"].map { |image| image["url"] }
    assert_equal "Seeds", payload.to_h["images"].first["alt"]
    refute_equal payload.identifier, build_payload(images: images.reverse).identifier
    refute_equal payload.identifier, build_payload(images: [ images.first.merge(sha256: "c" * 64), images.last ]).identifier
  end

  def test_faq_text_is_normalized_without_mutating_input_and_order_matters
    faq = [ { question: "  When to sow?", answer: "After frost.\r\n" }, { question: "How deep?", answer: "Two centimetres." } ]
    payload = build_payload(faq: faq)
    assert_equal({ "answer" => "After frost.", "question" => "When to sow?" }, payload.to_h["faq"].first)
    assert_equal "  When to sow?", faq.first[:question]
    assert_equal "After frost.\r\n", faq.first[:answer]
    refute_equal payload.identifier, build_payload(faq: faq.reverse).identifier
    refute_equal payload.identifier, build_payload(faq: faq.first(1)).identifier
    refute_equal payload.identifier, build_payload(faq: [ faq.first.merge(answer: "In March."), faq.last ]).identifier
  end

  def test_each_editor_text_field_changes_identity
    %i[title description search_title search_description body author].each do |key|
      refute_equal build_payload.identifier, build_payload(**{ key => "Different" }).identifier
    end
  end

  def test_post_mapping_uses_stored_byline_body_and_faq_with_cover_then_social
    image = Struct.new(:path, :sha256)
    post = Struct.new(:title, :description, :search_title, :search_description, :body_for_payload, :author_name, :faq_list, :cover_image, :cover_alt, :social_image).new(
      "Maple journal", nil, nil, nil, "Seeds sprout.\n", "Robin Vale", [],
      image.new("/notes/media/cover/seed.png", "d" * 64), "Seed packet",
      image.new("/notes/media/social/card.png", "e" * 64)
    )
    expected = build_payload(images: [
      { role: "cover", url: post.cover_image.path, sha256: "d" * 64, alt: "Seed packet" },
      { role: "social", url: post.social_image.path, sha256: "e" * 64, alt: "" }
    ])
    assert_equal expected.to_h, OpenBlog::RevisionPayload.new(post).to_h
    assert_equal expected.identifier, OpenBlog::RevisionPayload.new(post).identifier
  end

  private

  def build_payload(**overrides)
    OpenBlog::RevisionPayload.from_fields(**{
      title: "Maple journal", description: nil, search_title: nil, search_description: nil,
      body: "Seeds sprout.\n", author: "Robin Vale", images: [], faq: []
    }.merge(overrides))
  end
end
