require_relative "test_helper"
require "minitest/mock"

class ContentGuardTest < ActiveSupport::TestCase
  setup do
    @author = OpenBlog::Author.create!(name: "Rowan Gardener", slug: "rowan-gardener")
    @formats = OpenBlog.config.body_formats
    OpenBlog.config.body_formats = [ :markdown, :rich_text ]
  end

  teardown do
    OpenBlog.config.body_formats = @formats
  end

  test "direct FAQ create update and destroy each record the stored public content" do
    post = create_post
    faq = nil
    assert_difference "OpenBlog::Publication.count", 1 do
      faq = post.faqs.create!(position: 1, question: "How much?", answer: "One cup.")
    end
    assert_consistent(post)
    assert_difference "OpenBlog::Publication.count", 1 do
      faq.update!(answer: "Two cups.")
    end
    assert_consistent(post)
    assert_no_difference "OpenBlog::Publication.count" do
      faq.save!
    end
    assert_difference "OpenBlog::Publication.count", 1 do
      faq.destroy!
    end
    assert_consistent(post)
    assert_equal "substantive", post.publications.order(:id).last.entry_type
    assert_nil post.publications.order(:id).last.released_by
  end

  test "direct rich text create update and destroy use canonical stored bytes" do
    post = create_post(body_format: "rich_text", body_markdown: nil)
    assert_difference "OpenBlog::Publication.count", 1 do
      post.rich_body.update!(body: "<p class='tip'>Water gently<br/>Then wait.</p>")
    end
    assert_consistent(post)
    assert_no_difference "OpenBlog::Publication.count" do
      post.rich_body.save!
    end
    assert_difference "OpenBlog::Publication.count", 1 do
      post.rich_body.update!(body: "<p>Use <b>rainwater</b>.</p>")
    end
    assert_consistent(post)
    assert_difference "OpenBlog::Publication.count", 1 do
      post.rich_body.destroy!
    end
    assert_consistent(post)
  end

  test "nested FAQ replacement and rich text save produce one release per parent save" do
    post = create_post(body_format: "rich_text", body_markdown: nil)
    post.faqs.build(position: 1, question: "When?", answer: "At dawn.")
    post.rich_body = "<p>Start early.</p>"
    assert_difference "OpenBlog::Publication.count", 1 do
      post.save!
    end
    post.faqs.first.mark_for_destruction
    post.faqs.build(position: 2, question: "Where?", answer: "Near the window.")
    post.rich_body = "<p>Keep the pot shaded.</p>"
    assert_difference "OpenBlog::Publication.count", 1 do
      post.save!
    end
    assert_equal [ "Where?" ], post.reload.faqs.pluck(:question)
    assert_consistent(post)
  end

  test "operation FAQ replacements keep their declared release type and actor" do
    post = create_post
    post.faqs.create!(position: 1, question: "When?", answer: "At dawn.")
    assert_difference "OpenBlog::Publication.count", 1 do
      result = OpenBlog::Publish.call({ faq: [ { question: "How?", answer: "Gently." } ], change: "maintenance" },
        post: post, actor: "reviewer")
      assert result.success?, result.error&.message
    end
    entry = post.publications.order(:id).last
    assert_equal "maintenance", entry.entry_type
    assert_equal "reviewer", entry.released_by
    assert_consistent(post)
  end

  test "draft child changes refresh search and identity without creating records" do
    post = create_post(status: "draft")
    original = post.current_revision_identifier
    assert_no_difference [ "OpenBlog::Revision.count", "OpenBlog::Publication.count" ] do
      post.faqs.create!(position: 1, question: "Which soil?", answer: "Loose compost.")
    end
    refute_equal original, post.reload.current_revision_identifier
    assert_equal OpenBlog::RevisionPayload.new(post).identifier, post.current_revision_identifier
    assert_includes post.search_text, "Loose compost."
    rich = create_post(slug: "rich-draft", status: "draft", body_format: "rich_text")
    assert_no_difference [ "OpenBlog::Revision.count", "OpenBlog::Publication.count" ] do
      rich.rich_body.update!(body: "<p>Keep roots cool.</p>")
    end
    assert_equal OpenBlog::RevisionPayload.new(rich.reload).identifier, rich.current_revision_identifier
    assert_includes rich.search_text, "Keep roots cool."
  end

  test "release failures roll back direct child creates updates and destruction" do
    post = create_post
    faq = post.faqs.create!(position: 1, question: "How much?", answer: "One cup.")
    original = post.reload.attributes
    failure = ->(*) { raise "release unavailable" }
    OpenBlog::Publication.stub(:create!, failure) do
      assert_no_difference [ "OpenBlog::Faq.count", "OpenBlog::Revision.count", "OpenBlog::Publication.count" ] do
        assert_raises(RuntimeError) { faq.update!(answer: "Two cups.") }
        assert_raises(RuntimeError) { faq.reload.destroy! }
        assert_raises(RuntimeError) { post.faqs.create!(position: 2, question: "Which pot?", answer: "Clay.") }
      end
    end
    assert_equal "One cup.", faq.reload.answer
    assert_equal original, post.reload.attributes
    faq = OpenBlog::Faq.find(faq.id)
    assert_difference "OpenBlog::Publication.count", 1 do
      faq.update!(answer: "Three cups.")
    end
    assert_consistent(post)
  end

  test "rich text write failure rolls back body and public revision" do
    post = create_post(body_format: "rich_text")
    post.rich_body.update!(body: "<p>Original</p>")
    original_id = post.reload.public_revision_id
    OpenBlog::Publication.stub(:create!, ->(*) { raise "release unavailable" }) do
      assert_raises(RuntimeError) { post.rich_body.update!(body: "<p>Rejected</p>") }
    end
    assert_equal "<p>Original</p>", post.reload.body_for_payload
    assert_equal original_id, post.public_revision_id
    assert_consistent(post)
  end

  test "reparenting and direct callback bypasses are rejected" do
    first = create_post
    second = create_post(slug: "other-pot")
    faq = first.faqs.create!(position: 1, question: "Which pot?", answer: "Clay.")
    assert_raises(ActiveRecord::ReadOnlyRecord) { faq.update!(post: second) }
    faq.reload
    assert_raises(ActiveRecord::ReadOnlyRecord) { faq.update_columns(answer: "Plastic") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { faq.update_column(:question, "Why?") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { faq.delete }
    assert_raises(ActiveRecord::ReadOnlyRecord) { faq.increment!(:position) }
    assert_raises(ActiveRecord::ReadOnlyRecord) { faq.touch(:answer) }
    assert_equal first.id, faq.reload.post_id
    assert_equal "Clay.", faq.answer
  end

  test "rich text cannot leave the protected owner or name scope" do
    post = create_post(body_format: "rich_text")
    rich = post.rich_body
    rich.update!(body: "<p>Keep moist.</p>")
    assert_raises(ActiveRecord::ReadOnlyRecord) { rich.update!(name: "unprotected") }
    rich.reload
    assert_raises(ActiveRecord::ReadOnlyRecord) { rich.update!(record: @author) }
    rich.reload
    assert_raises(ActiveRecord::ReadOnlyRecord) { rich.update_columns(body: "untracked") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { rich.delete }
    assert_raises(ActiveRecord::ReadOnlyRecord) { rich.touch(:body) }
    assert_consistent(post)
  end

  test "unrelated rich text cannot enter a post body through callback bypasses" do
    post = create_post(body_format: "rich_text")
    other = ActionText::RichText.create!(record: @author, name: "biography", body: "<p>Gardener</p>")
    assert_raises(ActiveRecord::ReadOnlyRecord) do
      other.update_columns(record_type: "OpenBlog::Post", record_id: post.id, name: "rich_body")
    end
    assert_equal "OpenBlog::Author", other.reload.record_type
    assert_equal "biography", other.name
  end

  test "ordinary timestamp touches and unrelated host rich text remain available" do
    post = create_post(body_format: "rich_text")
    post.rich_body.update!(body: "<p>Keep moist.</p>")
    assert_no_difference "OpenBlog::Publication.count" do
      post.rich_body.touch
    end
    other = ActionText::RichText.create!(record: @author, name: "biography", body: "<p>Gardener</p>")
    assert_no_difference "OpenBlog::Publication.count" do
      other.update!(body: "<p>Experienced gardener</p>")
      other.update_columns(body: "<p>Updated</p>")
      other.delete
    end
    assert_consistent(post)
  end

  test "parent locks precede direct and nested FAQ writes" do
    post = create_post
    faq = post.faqs.create!(position: 1, question: "How?", answer: "Slowly.")
    [ -> { faq.update!(answer: "Gently.") }, -> { post.reload.faqs.load.first.answer = "Carefully."; post.save! } ].each do |write|
      statements = []
      subscriber = ->(_name, _start, _finish, _id, payload) { statements << payload[:sql] }
      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record", &write)
      parent_lock = statements.index { |sql| sql.match?(/SELECT.*open_blog_posts.*FOR UPDATE/) }
      child_write = statements.index { |sql| sql.match?(/UPDATE .?open_blog_faqs/) }
      if OpenBlog::Post.connection.adapter_name == "PostgreSQL"
        assert parent_lock, statements.join("\n")
        assert child_write, statements.join("\n")
        assert_operator parent_lock, :<, child_write
      end
      assert_consistent(post)
    end
  end

  test "parent context is cleared after a failed nested save" do
    post = create_post
    post.faqs.build(position: 1, question: "How?", answer: "Slowly.")
    OpenBlog::Publication.stub(:create!, ->(*) { raise "release unavailable" }) do
      assert_raises(RuntimeError) { post.save! }
    end
    refute OpenBlog::ContentGuard.active?(post)
    assert_difference "OpenBlog::Publication.count", 1 do
      post.reload.faqs.create!(position: 1, question: "How?", answer: "Gently.")
    end
    assert_consistent(post)
  end

  test "destroying an unrecorded draft with nested children creates no release" do
    post = create_post(status: "draft", body_format: "rich_text")
    post.rich_body.update!(body: "<p>Draft</p>")
    post.faqs.create!(position: 1, question: "Ready?", answer: "Soon.")
    assert_no_difference [ "OpenBlog::Revision.count", "OpenBlog::Publication.count" ] do
      post.destroy!
    end
    assert_empty OpenBlog::Faq.where(post_id: post.id)
    assert_empty ActionText::RichText.where(record_type: "OpenBlog::Post", record_id: post.id)
  end

  private

  def create_post(**attributes)
    OpenBlog::Post.create!({ title: "Watering a pot", slug: "watering-a-pot", body_markdown: "Use fresh water.",
      author: @author, author_name: @author.name, status: "published" }.merge(attributes))
  end

  def assert_consistent(post)
    post.reload
    payload = OpenBlog::RevisionPayload.new(post)
    assert_equal payload.identifier, post.current_revision_identifier
    assert_equal payload.identifier, post.public_revision.identifier
    assert_equal payload.to_json, post.public_revision.payload
  end
end
