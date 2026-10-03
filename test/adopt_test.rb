require_relative "test_helper"

class AdoptTest < ActiveSupport::TestCase
  setup do
    @now = Time.utc(2026, 8, 20, 12)
    @published = Time.utc(2024, 3, 10, 9)
    @modified = @published + 10.days
    @policy_urls = OpenBlog.config.policy_urls
    OpenBlog.config.policy_urls = { responsible_party: "https://example.test/about" }
  end

  teardown do
    OpenBlog.config.policy_urls = @policy_urls
  end

  test "adoption records evidenced dates and FAQ without a first publication" do
    result = adopt(first_published_at: @published, first_published_evidence: "Archived release log",
      last_modified_at: @modified, last_modified_evidence: "Saved change log",
      faq: [ { question: "How long?", answer: "A week." } ])
    assert result.success?, result.error&.message
    post = result.post.reload
    assert post.published?
    assert_equal @published, post.published_at
    assert_equal @modified, post.modified_at
    assert_equal [ "How long?" ], post.faqs.pluck(:question)
    assert_equal "adopted", post.publications.sole.entry_type
    assert_equal @now, post.publications.sole.occurred_at
    assert_equal "archive-export", post.baseline.source_system
    assert_equal "article-41", post.baseline.source_id
    assert_equal "Archived release log", post.baseline.first_published_evidence
    assert_equal({ revision: "new", publication: "adopted", approval: nil, baseline: "new", redirects: 0 }, result.records)
    assert_equal OpenBlog::RevisionPayload.new(post).identifier, post.public_revision.identifier
  end

  test "dates without evidence remain unknown and dates with evidence follow fallback order" do
    result = adopt(first_published_at: @published, last_modified_at: @modified)
    assert result.success?, result.error&.message
    assert_nil result.post.published_at
    assert_nil result.post.modified_at
    assert_nil result.post.baseline.first_published_at
    assert_nil result.post.baseline.last_modified_at
    result = adopt(first_published_at: @published, first_published_evidence: "Archived release log")
    assert result.success?, result.error&.message
    assert_equal @published, result.post.modified_at
  end

  test "publisher declaration preserves its distinct approval and declared date" do
    result = adopt(provenance: "ai_assisted", provenance_evidence: "Publisher statement on 2026-08-20",
      declaration: declaration.merge(declared_first_published_at: @published))
    assert result.success?, result.error&.message
    post = result.post
    approval = post.approvals.sole
    assert_equal "declared", approval.kind
    assert_equal "Taylor Reviewer", approval.reviewer_name
    assert_equal @published - 1.hour, approval.approved_at
    assert_equal Date.new(2026, 8, 20), approval.declared_on
    assert_equal "Morgan Publisher", approval.declared_by
    assert_equal post.public_revision_id, approval.revision_id
    assert_equal @published, post.published_at
    assert_equal @published, post.modified_at
    assert_nil post.baseline.first_published_at
    assert_equal @published, post.baseline.declared_first_published_at
    assert_equal "Publisher statement on 2026-08-20", post.provenance_evidence
    assert_equal :none, result.label
  end

  test "false declaration is retained and incomplete declaration fields are refused" do
    result = adopt(declaration: declaration.merge(facts_checked: false))
    assert result.success?, result.error&.message
    assert_equal false, result.post.approvals.sole.facts_checked
    assert_includes result.findings.map { |finding| finding[:code] }, :approval_incomplete
    %i[declared_by declared_on].each do |field|
      result = adopt(declaration: declaration.except(field))
      refute result.success?
      assert_equal :validation_failed, result.error.code
      assert_includes result.error.details, "declaration.#{field}"
    end
  end

  test "malformed reviewer names and fact check values use the approval error" do
    [ declaration.merge(reviewer_name: ""), declaration.except(:reviewer_name), declaration.merge(facts_checked: "true") ].each do |value|
      result = adopt(declaration: value)
      refute result.success?
      assert_equal :approval_incomplete, result.error.code
    end
  end

  test "evidenced and declared first dates cannot be mixed" do
    assert_no_difference "OpenBlog::Post.count" do
      result = adopt(first_published_at: @published, first_published_evidence: "Release log",
        declaration: declaration.merge(declared_first_published_at: @published))
      refute result.success?
      assert_equal :validation_failed, result.error.code
      assert_includes result.error.details, "declaration.declared_first_published_at"
    end
  end

  test "imported approval requires evidence and confirmation" do
    imported = { reviewer_name: "Taylor Reviewer", approved_at: @published - 1.hour, facts_checked: true,
      evidence: "Archived approval record", confirmed_by: "Morgan Publisher" }
    result = adopt(imported_approval: imported)
    assert result.success?, result.error&.message
    approval = result.post.approvals.sole
    assert_equal "imported", approval.kind
    assert_equal "Archived approval record", approval.evidence
    assert_equal "Morgan Publisher", approval.confirmed_by
    result = adopt(imported_approval: imported.except(:confirmed_by))
    refute result.success?
    assert_includes result.error.details, "imported_approval.confirmed_by"
    result = adopt(imported_approval: imported, declaration: declaration)
    refute result.success?
  end

  test "required inputs unsupported slugs unknown fields and provenance evidence are checked" do
    %i[source_system source_id slug title body body_format].each do |field|
      result = OpenBlog::Adopt.call(content.except(field), actor: "importer", now: @now)
      refute result.success?, field.to_s
      assert_includes result.error.details, field.to_s
    end
    [ "Dotted.Slug", "Upper-case" ].each do |slug|
      result = adopt(slug: slug)
      assert_equal :slug_not_supported, result.error.code
    end
    result = adopt(approval: { name: "Reviewer", facts_checked: true })
    assert_equal :unknown_field, result.error.code
    assert_equal [ "approval" ], result.error.details
    result = adopt(provenance: "human_written")
    refute result.success?
    assert_includes result.error.details, "provenance_evidence"
    result = adopt(provenance: "human_written", declaration: declaration)
    assert result.success?, result.error&.message
    assert_includes result.post.provenance_evidence, "Morgan Publisher"
    assert_includes result.post.provenance_evidence, "2026-08-20"
  end

  test "optional evidence and category text reject false values" do
    %i[category_description provenance_evidence first_published_evidence last_modified_evidence].each do |field|
      result = adopt(**{ field => false })
      refute result.success?, field.to_s
      assert_equal :validation_failed, result.error.code
      assert_includes result.error.details, field.to_s
    end
  end

  test "false source digests fail contract normalization" do
    error = assert_raises(OpenBlog::Error::ValidationFailed) do
      OpenBlog::Adopt::Contract.new(content.merge(source_body_sha256: false))
    end
    assert_includes error.details, "source_body_sha256"
  end

  test "false redirect dates are refused" do
    result = adopt(old_slugs: [ { slug: "former-orchard", moved_on: false } ])
    refute result.success?
    assert_equal :validation_failed, result.error.code
    assert_includes result.error.details, "old_slugs.moved_on"
  end

  test "submicrosecond evidence timestamps repeat without replacing stored records" do
    published = Time.iso8601("2024-03-10T09:00:00.123456789Z")
    approved = Time.iso8601("2024-03-10T08:00:00.987654321Z")
    attributes = { first_published_at: published, first_published_evidence: "Archived release log",
      last_modified_at: published + 10.days, last_modified_evidence: "Archived update log",
      declaration: declaration.merge(approved_at: approved) }
    first = adopt(**attributes)
    assert first.success?, first.error&.message
    post = first.post
    identity = [ post.public_revision_id, post.baseline.id, post.approvals.sole.id, post.updated_at ]
    again = adopt(**attributes)
    assert again.success?, again.error&.message
    assert_nil again.records[:publication]
    assert_equal identity, [ post.reload.public_revision_id, post.baseline.id, post.approvals.sole.id, post.updated_at ]
    assert_equal 123456000, post.published_at.nsec
    assert_equal 987654000, post.approvals.sole.approved_at.nsec
  end

  test "old slugs preserve move dates and reject another posts URL" do
    result = adopt(old_slugs: [ "previous-orchard", { slug: "first-orchard", moved_on: "2023-05-09" } ])
    assert result.success?, result.error&.message
    redirects = OpenBlog::Redirect.where(post: result.post).order(:old_path)
    assert_equal 2, redirects.count
    assert_equal [ "adoption" ], redirects.reorder(nil).distinct.pluck(:source)
    assert_equal result.post.path, redirects.first.new_path
    assert_equal Date.new(2023, 5, 9), redirects.first.occurred_on
    assert_equal @now.to_date, redirects.last.occurred_on
    assert_equal 2, result.records[:redirects]
    other = OpenBlog::SaveDraft.call({ title: "Another article", slug: "occupied" }, actor: "editor").post
    result = adopt(old_slugs: [ other.slug ])
    refute result.success?
    assert_equal :slug_reserved, result.error.code
  end

  test "category description only fills an absent description" do
    first = adopt(category: "Trees", category_description: "Notes about trees")
    assert first.success?, first.error&.message
    assert_equal "Notes about trees", first.post.category.description
    second = adopt(source_id: "article-42", slug: "another-tree", category: "Trees", category_description: "Replacement text")
    assert second.success?, second.error&.message
    assert_equal "Notes about trees", second.post.category.description
  end

  test "same snapshot is a no-op and body replacement removes previous adoption records" do
    first = adopt(declaration: declaration, old_slugs: [ "old-orchard" ])
    assert first.success?, first.error&.message
    post = first.post
    original = [ post.attributes, post.baseline.attributes, post.public_revision.attributes, post.approvals.sole.attributes ]
    again = OpenBlog::Adopt.call(content.merge(declaration: declaration, old_slugs: [ "old-orchard" ]), actor: "importer", now: @now + 1.day)
    assert again.success?, again.error&.message
    assert_nil again.records[:publication]
    assert_equal original, [ post.reload.attributes, post.baseline.attributes, post.public_revision.attributes, post.approvals.sole.attributes ]
    old_ids = [ post.baseline.id, post.public_revision_id, post.approvals.sole.id, post.publications.sole.id ]
    replaced = adopt(body: "A revised orchard article.")
    assert replaced.success?, replaced.error&.message
    assert_equal "replaced", replaced.records[:baseline]
    assert_equal 1, post.publications.count
    assert_equal "adopted", post.publications.sole.entry_type
    assert_empty post.approvals
    [ OpenBlog::Baseline, OpenBlog::Revision, OpenBlog::Approval, OpenBlog::Publication ].zip(old_ids).each do |model, id|
      refute model.exists?(id)
    end
  end

  test "same payload metadata changes reconcile before edits and later releases refuse replacement" do
    first = adopt(tags: [ "Garden" ])
    original_identifier = first.post.current_revision_identifier
    updated = adopt(tags: [ "Trees" ], featured: true, first_published_at: @published, first_published_evidence: "Release log")
    assert updated.success?, updated.error&.message
    assert_equal original_identifier, updated.post.current_revision_identifier
    assert_equal [ "Trees" ], updated.post.tags.pluck(:name)
    assert updated.post.featured?
    assert_equal @published, updated.post.published_at
    published = OpenBlog::Publish.call({ body: "An editorial update", change: "substantive" }, post: updated.post, actor: "editor")
    assert published.success?, published.error&.message
    result = adopt(body: "Another source update")
    refute result.success?
    assert_equal :already_changed_in_gem, result.error.code
    assert_equal "An editorial update", updated.post.reload.body_markdown
  end

  test "existing draft can be adopted but a foreign source cannot claim an adopted post" do
    draft = OpenBlog::SaveDraft.call({ title: "Earlier draft", slug: content[:slug] }, actor: "editor").post
    result = adopt
    assert result.success?, result.error&.message
    assert_equal draft.id, result.post.id
    result = adopt(source_system: "another-export")
    refute result.success?
    assert_equal :identity_conflict, result.error.code
    assert_equal "archive-export", draft.reload.baseline.source_system
  end

  test "reimport preserves connection history and appends only a changed declaration" do
    declaration = { connections: [], third_party_paid: false, declared_by: "Publisher", declared_on: "2026-08-20" }
    first = adopt(connections: declaration)
    assert first.success?, first.error&.message
    original = first.post.connection_declarations.sole.id
    repeated = adopt(connections: declaration)
    assert repeated.success?, repeated.error&.message
    assert_nil repeated.records[:publication]
    omitted = adopt
    assert omitted.success?, omitted.error&.message
    assert_nil omitted.records[:publication]
    changed = adopt(connections: declaration.merge(third_party_paid: true))
    assert changed.success?, changed.error&.message
    assert_equal 2, changed.post.connection_declarations.count
    assert OpenBlog::ConnectionDeclaration.exists?(original)
    assert_equal true, changed.post.connection_declarations.order(:id).last.third_party_paid
  end

  test "reimport cannot resurrect unpublished or removed content" do
    [ OpenBlog::Unpublish, OpenBlog::Remove ].each_with_index do |operation, index|
      input = { source_id: "lifecycle-#{index}", slug: "lifecycle-#{index}" }
      first = adopt(**input)
      assert first.success?, first.error&.message
      assert operation.call(first.post, actor: "editor").success?
      previous = first.post.reload.attributes
      result = adopt(**input)
      refute result.success?
      assert_equal :already_changed_in_gem, result.error.code
      assert_equal previous, first.post.reload.attributes
      assert_nil OpenBlog::Redirect.find_by!(old_path: first.post.path).new_path
    end
  end

  test "a later slug change blocks replacing adoption history" do
    first = adopt
    moved = OpenBlog::Publish.call({ slug: "a-new-address" }, post: first.post, actor: "editor")
    assert moved.success?, moved.error&.message
    assert_equal 1, moved.post.publications.count
    result = adopt
    refute result.success?
    assert_equal :already_changed_in_gem, result.error.code
    assert_equal "a-new-address", first.post.reload.slug
  end

  test "dry run reports the candidate and rolls back every affected record" do
    models = [ OpenBlog::Post, OpenBlog::Author, OpenBlog::Category, OpenBlog::Tag, OpenBlog::Tagging,
      OpenBlog::Faq, OpenBlog::Revision, OpenBlog::Publication, OpenBlog::Baseline, OpenBlog::Approval, OpenBlog::Redirect ]
    counts = models.map(&:count)
    result = adopt(dry_run: true, category: "Fruit", tags: [ "Trees" ], declaration: declaration,
      faq: [ { question: "How?", answer: "With care." } ], old_slugs: [ "older-orchard" ])
    assert result.success?, result.error&.message
    assert result.dry_run
    assert_equal "Orchard care", result.post.title
    assert_equal "Water young trees.", result.post.body_markdown
    assert_equal counts, models.map(&:count)
  end

  private

  def content
    { source_system: "archive-export", source_id: "article-41", slug: "orchard-care", title: "Orchard care",
      body_format: "markdown", body: "Water young trees." }
  end

  def declaration
    { reviewer_name: "Taylor Reviewer", approved_at: @published - 1.hour, facts_checked: true,
      declared_on: "2026-08-20", declared_by: "Morgan Publisher" }
  end

  def adopt(**attributes)
    OpenBlog::Adopt.call(content.merge(attributes), actor: "importer", now: @now)
  end
end
