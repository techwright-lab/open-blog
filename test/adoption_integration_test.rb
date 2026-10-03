require_relative "test_helper"

class AdoptionIntegrationTest < ActiveSupport::TestCase
  setup do
    @now = Time.utc(2026, 9, 12, 10)
  end

  test "metadata changes with an unchanged payload are reconciled and repeated import is a no op" do
    first = adopt
    assert first.success?, first.error&.message
    identifier = first.post.current_revision_identifier
    changed = adopt(canonical_url: "https://archive.example/seed-notes", tags: [ "archive" ])
    assert changed.success?, changed.error&.message
    assert_equal identifier, changed.post.current_revision_identifier
    assert_equal "https://archive.example/seed-notes", changed.post.canonical_url
    assert_equal [ "archive" ], changed.post.tags.pluck(:name)
    before = snapshot(changed.post)
    again = adopt(canonical_url: "https://archive.example/seed-notes", tags: [ "archive" ])
    assert again.success?
    assert_equal before, snapshot(again.post)
  end

  test "declaration changes with the same content replace the baseline before later publication" do
    first = adopt(declaration: declaration(facts_checked: false))
    assert first.success?, first.error&.message
    identifier = first.post.current_revision_identifier
    changed = adopt(declaration: declaration(facts_checked: true))
    assert changed.success?, changed.error&.message
    assert_equal identifier, changed.post.current_revision_identifier
    assert_equal true, changed.post.approvals.sole.facts_checked
    assert_equal 1, changed.post.publications.count
    assert_equal "adopted", changed.post.publications.sole.entry_type
  end

  test "a source cannot take over a different previously published identity" do
    public_post = OpenBlog::Publish.call({ title: "Seed notes", slug: "seed-notes", body: "New content" }, actor: "Editor").post
    original = snapshot(public_post)
    refused = adopt
    refute refused.success?
    assert_equal original, snapshot(public_post.reload)
    assert_nil public_post.baseline
  end

  test "adoption reports when its full snapshot uses the configured default author" do
    assert_includes adopt.findings.pluck(:code), :author_default_used
    explicit = adopt(author: { name: "Named Archivist" })
    assert explicit.success?, explicit.error&.message
    refute_includes explicit.findings.pluck(:code), :author_default_used
  end

  test "a full import clears omitted FAQ and tags without copying old approvals" do
    first = adopt(tags: [ "historic" ], faq: [ { question: "Where?", answer: "In the greenhouse." } ], declaration: declaration(facts_checked: true))
    assert first.success?
    changed = adopt(body: "Use a fresh seed tray.")
    assert changed.success?, changed.error&.message
    assert_empty changed.post.faqs
    assert_empty changed.post.tags
    assert_empty changed.post.approvals
    assert_equal 1, changed.post.revisions.count
  end

  test "dry run returns proposed content while leaving every table unchanged" do
    first = adopt
    assert first.success?
    tables = ActiveRecord::Base.connection.tables - %w[schema_migrations ar_internal_metadata]
    counts = tables.to_h { |table| [ table, ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM #{ActiveRecord::Base.connection.quote_table_name(table)}") ] }
    original = snapshot(first.post)
    result = adopt(body: "Proposed replacement", dry_run: true, tags: [ "new preview tag" ])
    assert result.success?, result.error&.message
    assert result.dry_run
    assert_equal "Proposed replacement", result.post.body_markdown
    assert_equal original, snapshot(first.post.reload)
    assert_equal counts, tables.to_h { |table| [ table, ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM #{ActiveRecord::Base.connection.quote_table_name(table)}") ] }
  end

  test "FAQ sections in Markdown are reported with or without FAQ records" do
    author = OpenBlog::Author.create!(name: "Archive Writer", slug: "archive-writer")
    post = OpenBlog::Post.create!(title: "Seed notes", slug: "seed-notes", author: author, author_name: author.name,
      body_markdown: "## FAQ\n\n### Where?\n\nIn a seed tray.\n")
    assert_includes OpenBlog::Findings.for(post).pluck(:code), :faq_in_body
    post.faqs.create!(position: 1, question: "Where?", answer: "In a seed tray.")
    assert_includes OpenBlog::Findings.for(post.reload).pluck(:code), :faq_in_body
    post.update!(body_markdown: "A body without a question section.")
    refute_includes OpenBlog::Findings.for(post).pluck(:code), :faq_in_body
  end

  test "any later release refuses adoption even when the submitted snapshot matches live content" do
    first = adopt
    published = OpenBlog::Publish.call({ body: "Edited after import", change: "substantive" }, post: first.post, actor: "Editor")
    assert published.success?, published.error&.message
    original = snapshot(published.post)
    refused = adopt(body: "Edited after import")
    refute refused.success?
    assert_equal :already_changed_in_gem, refused.error.code
    assert_equal original, snapshot(published.post)
  end

  test "an unchanged maintenance release still closes adoption replacement" do
    first = adopt
    published = OpenBlog::Publish.call({ change: "maintenance" }, post: first.post, actor: "Editor")
    assert published.success?, published.error&.message
    refused = adopt
    refute refused.success?
    assert_equal :already_changed_in_gem, refused.error.code
    assert_equal 2, first.post.publications.count
  end

  test "dry run retains a complete candidate graph after its transaction rolls back" do
    [ false, true ].each do |existing|
      adopt if existing
      result = adopt(body: "Candidate preview", dry_run: true, provenance: "human_written", provenance_evidence: "Archive record",
        category: "Preview category", tags: [ "Preview tag" ],
        faq: [ { question: "Ready?", answer: "Almost." } ], declaration: declaration(facts_checked: true))
      assert result.success?, result.error&.message
      candidate = result.post
      assert_equal candidate.current_revision_identifier, candidate.public_revision&.identifier
      assert_equal "Candidate preview", JSON.parse(candidate.public_revision.payload)["body"]
      assert_equal "human_written", candidate.baseline.provenance
      assert_equal [ "Preview tag" ], candidate.tags.map(&:name)
      assert_equal [ "Ready?" ], candidate.faqs.map(&:question)
      assert_equal [ "declared" ], candidate.approvals.map(&:kind)
      assert_equal [ "adopted" ], candidate.publications.map(&:entry_type)
      assert_equal [ candidate.current_revision_identifier ], candidate.revisions.map(&:identifier)
      assert_equal "Preview category", candidate.category.name
      assert_equal "Keep the tray moist.", OpenBlog::Post.find(candidate.id).body_markdown if existing
    end
  end

  private

  def adopt(**attributes)
    OpenBlog::Adopt.call({ source_system: "archive", source_id: "seed-1", slug: "seed-notes", title: "Seed notes", body_format: "markdown", body: "Keep the tray moist." }.merge(attributes), actor: "Archivist", now: @now)
  end

  def declaration(facts_checked:)
    { reviewer_name: "Reviewer", approved_at: "2020-03-01T10:00:00Z", facts_checked: facts_checked,
      declared_on: "2026-09-12", declared_by: "Publisher" }
  end

  def snapshot(post)
    { post: post.reload.attributes, baseline: post.baseline&.attributes, revisions: post.revisions.order(:id).map(&:attributes),
      approvals: post.approvals.order(:id).map(&:attributes), publications: post.publications.order(:id).map(&:attributes),
      tags: post.tags.order(:id).pluck(:name), faqs: post.faqs.map(&:attributes) }
  end
end
