require_relative "test_helper"

class PostTest < ActiveSupport::TestCase
  setup do
    @author = OpenBlog::Author.create!(name: "Jordan Writer", slug: "jordan-writer")
  end

  test "one save hashes and stores the in-memory FAQ list in display order" do
    post = build_post
    post.faqs.build(position: 2, question: "  Can I edit it?", answer: "Yes.\r\n")
    post.faqs.build(position: 1, question: "What is this?", answer: "A short article.")
    expected = OpenBlog::RevisionPayload.new(post).identifier

    post.save!
    assert_equal expected, post.current_revision_identifier
    assert_equal [ "What is this?", "  Can I edit it?" ], post.faq_list.map { |entry| entry[:question] }
    assert_equal "Yes.\r\n", post.faqs.find_by!(position: 2).answer
    assert_equal expected, OpenBlog::RevisionPayload.new(post.reload).identifier
  end

  test "loaded FAQ edits ordering additions and destruction affect the payload before saving" do
    post = build_post
    post.faqs.build(position: 1, question: "First?", answer: "Answer one.")
    post.faqs.build(position: 2, question: "Second?", answer: "Answer two.")
    post.save!
    post.faqs.load
    initial = post.current_revision_identifier
    post.faqs.first.question = "Revised question?"
    refute_equal initial, OpenBlog::RevisionPayload.new(post).identifier
    post.save!
    edited = post.current_revision_identifier
    post.faqs.first.position = 3
    assert_equal "Second?", post.faq_list.first[:question]
    refute_equal edited, OpenBlog::RevisionPayload.new(post).identifier
    post.faqs.first.mark_for_destruction
    post.faqs.build(position: 4, question: "New?", answer: "Answer three.")
    expected = OpenBlog::RevisionPayload.new(post).identifier
    post.save!
    assert_equal [ "Second?", "New?" ], post.reload.faq_list.map { |entry| entry[:question] }
    assert_equal expected, post.current_revision_identifier
  end

  test "editor content fields change revision identity while metadata does not" do
    post = build_post
    post.save!
    original = post.current_revision_identifier
    %i[title description search_title search_description body_markdown author_name].each do |field|
      old_value = post.public_send(field)
      post.public_send("#{field}=", "Changed content")
      refute_equal original, OpenBlog::RevisionPayload.new(post).identifier, field.to_s
      post.public_send("#{field}=", old_value)
    end
    post.assign_attributes(slug: "different-slug", featured: true, canonical_url: "https://example.test/elsewhere",
      provenance: "human_written", status: "scheduled", published_at: Time.current,
      category: OpenBlog::Category.new(name: "Notes", slug: "notes"),
      series: OpenBlog::Series.new(name: "Examples", slug: "examples"), series_position: 1)
    post.tags.build(name: "Ruby", slug: "ruby")
    assert_equal original, OpenBlog::RevisionPayload.new(post).identifier
  end

  test "rich text hashes the exact serialized body before and after persistence" do
    original_formats = OpenBlog.config.body_formats
    OpenBlog.config.body_formats = [ :markdown, :rich_text ]
    post = build_post(body_format: "rich_text")
    source = "<p class='note'>A paragraph<br/>Another line.</p>"
    post.rich_body = source
    expected_body = post.rich_body.read_attribute_for_database(:body)
    refute_equal source, expected_body
    assert_equal expected_body, post.body_for_payload
    expected = OpenBlog::RevisionPayload.new(post).identifier
    post.save!
    sql = ActionText::RichText.where(record: post, name: "rich_body").select(:body).to_sql
    stored_body = ActionText::RichText.connection.select_value(sql)
    assert_equal expected_body, stored_body
    assert_equal expected, post.current_revision_identifier
    assert_equal expected_body, post.reload.body_for_payload
    assert_equal expected, OpenBlog::RevisionPayload.new(post).identifier
    post.rich_body = "<div>Next <b>draft</b><br/></div>"
    updated = OpenBlog::RevisionPayload.new(post).identifier
    refute_equal expected, updated
    post.save!
    assert_equal updated, OpenBlog::RevisionPayload.new(post.reload).identifier
  ensure
    OpenBlog.config.body_formats = original_formats
  end

  test "author rename leaves the stored byline and identifier unchanged" do
    post = build_post
    post.save!
    identifier = post.current_revision_identifier
    @author.update!(name: "A New Name")
    assert_equal "Jordan Writer", post.reload.author_name
    assert_equal identifier, OpenBlog::RevisionPayload.new(post).identifier
  end

  test "word count reading time and search include body and FAQ text" do
    post = build_post(body_markdown: "# Notes\n\nOne [useful link](https://example.test/hidden) ![diagram](photo.png)\n\n```ruby\nputs 'hello'\n```\n")
    post.faqs.build(position: 1, question: "Why now?", answer: "Because it works.")
    post.save!
    assert_equal 12, post.word_count
    assert_equal 1, post.reading_time_minutes
    assert_includes post.search_text, "Why now?"
    assert_includes post.search_text, "Because it works."
    assert_includes post.search_text, "puts 'hello'"
    refute_includes post.search_text, "https://example.test/hidden"
    post.update!(body_markdown: ([ "word" ] * 477).join(" "))
    assert_equal 482, post.word_count
    assert_equal 3, post.reading_time_minutes
  end

  test "slug validation reserves fixed and configured route segments" do
    [ "feed", "search", "preview", "media", "policies", "api", "mcp", "sitemap", "category", "My.Post", "two--words" ].each do |slug|
      post = build_post(slug: slug)
      refute post.valid?, slug
      assert post.errors[:slug].any?, slug
    end
    assert build_post(slug: "my-post_2").valid?
    original = OpenBlog.config.route_segments
    OpenBlog.config.route_segments = original.merge(category: "topics")
    refute build_post(slug: "topics").valid?
  ensure
    OpenBlog.config.route_segments = original if original
  end

  test "canonical URLs must be absolute HTTP URLs and formats must be enabled" do
    [ "/relative", "javascript:alert(1)", "https://", "https://example.test/has space" ].each do |url|
      post = build_post(canonical_url: url)
      refute post.valid?, url
      assert post.errors[:canonical_url].any?, url
    end
    assert build_post(canonical_url: "https://example.test/original?source=blog").valid?
    post = build_post(body_format: "rich_text")
    refute post.valid?
    assert post.errors[:body_format].any?
  end

  test "path and URL follow the mount and caller base" do
    post = build_post
    assert_equal "/blog/example-post", post.path
    assert_equal "https://example.test/blog/example-post", post.url
    original = OpenBlog.config.public_base_url
    OpenBlog.config.public_base_url = nil
    assert_nil post.url
    assert_equal "http://localhost:3000/blog/example-post", post.url(base: "http://localhost:3000/")
  ensure
    OpenBlog.config.public_base_url = original
  end

  test "listed scope contains published posts only" do
    %w[draft scheduled published archived].each { |status| build_post(slug: status, status: status).save! }
    assert_equal [ "published" ], OpenBlog::Post.listed.pluck(:status)
  end

  test "cover social image and alternative text participate in identity" do
    post = build_post
    post.cover_image = OpenBlog::Image.new(sha256: "a" * 64, filename: "cover.png", content_type: "image/png", byte_size: 1)
    initial = OpenBlog::RevisionPayload.new(post).identifier
    post.cover_alt = "A mountain at dawn"
    refute_equal initial, OpenBlog::RevisionPayload.new(post).identifier
    changed_alt = OpenBlog::RevisionPayload.new(post).identifier
    post.social_image = OpenBlog::Image.new(sha256: "b" * 64, filename: "social.png", content_type: "image/png", byte_size: 1)
    refute_equal changed_alt, OpenBlog::RevisionPayload.new(post).identifier
    post.cover_image = nil
    assert_equal [ "social" ], OpenBlog::RevisionPayload.new(post).to_h["images"].map { |image| image["role"] }
  end

  test "redirect paths remain reserved except for their existing post" do
    post = build_post
    post.save!
    OpenBlog::Redirect.create!(old_path: "/blog/previous-slug", source: "manual", occurred_on: Date.current, post: post)
    refute build_post(slug: "previous-slug").valid?
    post.slug = "previous-slug"
    assert post.valid?
    OpenBlog::Redirect.create!(old_path: "/blog/unowned", source: "manual", occurred_on: Date.current)
    refute build_post(slug: "unowned").valid?
  end

  test "public revision must belong to the same post" do
    post = build_post
    post.save!
    other = build_post(slug: "another-post")
    other.save!
    revision = OpenBlog::Revision.create!(post: other, identifier: other.current_revision_identifier,
      payload: OpenBlog::RevisionPayload.new(other).to_json)
    post.public_revision = revision
    refute post.valid?
    assert post.errors[:public_revision].any?
  end

  private

  def build_post(**attributes)
    OpenBlog::Post.new({ slug: "example-post", title: "Example post", author: @author,
      author_name: @author.name, body_markdown: "A simple paragraph." }.merge(attributes))
  end
end
