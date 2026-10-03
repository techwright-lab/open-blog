require_relative "test_helper"
require "stringio"

class RecordModelsTest < ActiveSupport::TestCase
  setup do
    @author = OpenBlog::Author.create!(name: "Ada Example")
    @post = OpenBlog::Post.create!(title: "Example", slug: "example", author: @author, author_name: @author.name, body_format: "markdown", body_markdown: "Example body")
    @revision = OpenBlog::Revision.create!(post: @post, identifier: "a" * 64, payload: "{}")
  end

  test "all six immutable records permit insertion and refuse persisted mutation" do
    records = [
      OpenBlog::Image.create!(sha256: "b" * 64, filename: "example.png", content_type: "image/png", byte_size: 5),
      @revision,
      OpenBlog::Approval.create!(post: @post, revision: @revision, kind: "sent", reviewer_name: "Ada", facts_checked: false, approved_at: Time.current),
      OpenBlog::Publication.create!(post: @post, revision: @revision, entry_type: "first", occurred_at: Time.current),
      OpenBlog::Baseline.create!(post: @post, adopted_revision: @revision, adopted_at: Time.current, provenance: "unknown"),
      OpenBlog::ConnectionDeclaration.create!(post: @post, connections: [], third_party_paid: false, declared_by: "Ada", declared_on: Date.current)
    ]
    records.each do |record|
      assert record.persisted?
      assert record.readonly?
      assert_raises(ActiveRecord::ReadOnlyRecord) { record.save! }
      assert_raises(ActiveRecord::ReadOnlyRecord) { record.save }
      assert_raises(ActiveRecord::ReadOnlyRecord) { record.update(created_at: 1.day.ago) }
      assert_raises(ActiveRecord::ReadOnlyRecord) { record.update_columns(created_at: 1.day.ago) }
      assert_raises(ActiveRecord::ReadOnlyRecord) { record.touch }
      assert_raises(ActiveRecord::ReadOnlyRecord) { record.destroy }
    end
    records.reverse_each { |record| assert_equal 1, record.class.where(id: record.id).delete_all }
  end

  test "image paths encode filenames under the configured mount" do
    image = OpenBlog::Image.new(sha256: "b" * 64, filename: "an image #1.png")
    assert_equal "/blog/media/#{"b" * 64}/an%20image%20%231.png", image.path
  end

  test "stored images keep their attached bytes and prohibit attachment API mutation" do
    image = OpenBlog::Image.create!(sha256: Digest::SHA256.hexdigest("image"), filename: "example.png", content_type: "image/png", byte_size: 5,
      file: { io: StringIO.new("image"), filename: "example.png", content_type: "image/png" })
    assert_equal "image", image.reload.file.download
    %i[detach purge purge_later].each do |operation|
      assert_raises(ActiveRecord::ReadOnlyRecord) { image.file.public_send(operation) }
    end
    assert_raises(ActiveRecord::ReadOnlyRecord) { image.file.attach(io: StringIO.new("other"), filename: "other.png") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { image.file = nil }
    assert_equal "image", image.reload.file.download
  ensure
    image&.file&.blob&.service&.delete(image.file.blob.key) if image&.file&.attached?
  end

  test "taxonomy models generate slugs and preserve associations" do
    category = OpenBlog::Category.create!(name: "Release Notes")
    series = OpenBlog::Series.create!(name: "Getting Started")
    tag = OpenBlog::Tag.create!(name: "Ruby on Rails")
    @post.update!(category: category, series: series, series_position: 1)
    @post.tags << tag
    assert_equal "release-notes", category.slug
    assert_equal "getting-started", series.slug
    assert_equal "ruby-on-rails", tag.slug
    assert_equal [ @post ], category.posts.to_a
    assert_equal [ @post ], series.posts.to_a
    assert_equal [ @post ], tag.posts.to_a
    refute OpenBlog::Tag.new(name: "ruby ON rails", slug: "another-tag").valid?
  end

  test "FAQ text retains submitted bytes" do
    faq = @post.faqs.create!(position: 1, question: "  A question?", answer: "An answer.\r\n")
    assert_equal "  A question?", faq.reload.question
    assert_equal "An answer.\r\n", faq.answer
    refute @post.faqs.build(position: 0, question: "Q", answer: "A").valid?
  end

  test "imported and declared approvals require their supporting fields" do
    attributes = { post: @post, revision: @revision, reviewer_name: "Ada", facts_checked: false, approved_at: Time.current }
    imported = OpenBlog::Approval.new(**attributes, kind: "imported")
    refute imported.valid?
    imported.assign_attributes(confirmed_by: "Ada", evidence: "Archived approval record")
    assert imported.valid?
    declared = OpenBlog::Approval.new(**attributes, kind: "declared")
    refute declared.valid?
    declared.assign_attributes(declared_by: "Ada", declared_on: Date.current)
    assert declared.valid?
    declared.facts_checked = nil
    refute declared.valid?
  end

  test "records cannot claim revisions belonging to another post" do
    other = OpenBlog::Post.create!(title: "Other", slug: "other", author: @author, author_name: @author.name, body_format: "markdown")
    records = [
      OpenBlog::Approval.new(post: other, revision: @revision, kind: "sent", reviewer_name: "Ada", facts_checked: true, approved_at: Time.current),
      OpenBlog::Publication.new(post: other, revision: @revision, entry_type: "first", occurred_at: Time.current),
      OpenBlog::Baseline.new(post: other, adopted_revision: @revision, adopted_at: Time.current, provenance: "unknown")
    ]
    records.each { |record| refute record.valid?, record.class.name }
  end

  test "declared dates do not become evidenced publication dates" do
    baseline = OpenBlog::Baseline.create!(post: @post, adopted_revision: @revision, adopted_at: Time.current, provenance: "unknown", declared_first_published_at: 1.year.ago)
    assert_nil baseline.reload.first_published_at
    assert baseline.declared_first_published_at
    baseline.first_published_at = 1.year.ago
    refute baseline.valid?
  end

  test "database permits repeated releases but rejects a second first publication" do
    attributes = { post_id: @post.id, revision_id: @revision.id, entry_type: "first", occurred_at: Time.current, created_at: Time.current }
    OpenBlog::Publication.insert_all!([ attributes ])
    assert_raises(ActiveRecord::RecordNotUnique) do
      ActiveRecord::Base.transaction(requires_new: true) { OpenBlog::Publication.insert_all!([ attributes ]) }
    end
    2.times { OpenBlog::Publication.insert_all!([ attributes.merge(entry_type: "maintenance") ]) }
    assert_equal 3, @post.publications.count
  end

  test "database rejects dangling foreign keys and mixed baseline dates" do
    assert_raises(ActiveRecord::InvalidForeignKey) do
      ActiveRecord::Base.transaction(requires_new: true) { OpenBlog::Faq.insert_all!([ { post_id: -1, position: 1, question: "Q", answer: "A", created_at: Time.current, updated_at: Time.current } ]) }
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      ActiveRecord::Base.transaction(requires_new: true) do
        OpenBlog::Baseline.insert_all!([ { post_id: @post.id, adopted_revision_id: @revision.id, adopted_at: Time.current, provenance: "unknown", first_published_at: Time.current, declared_first_published_at: Time.current, created_at: Time.current } ])
      end
    end
  end

  test "corrections require notes and declarations allow explicit none" do
    publication = OpenBlog::Publication.new(post: @post, revision: @revision, entry_type: "correction", occurred_at: Time.current)
    refute publication.valid?
    publication.note = "Corrected a date"
    assert publication.valid?
    declaration = OpenBlog::ConnectionDeclaration.new(post: @post, third_party_paid: false, declared_by: "Ada", declared_on: Date.current)
    assert declaration.valid?
    declaration.connections = [ { party: "Example", relation: "Sponsor" } ]
    assert declaration.valid?
    declaration.connections = [ { party: "Example" } ]
    refute declaration.valid?
  end

  test "redirects only allow the target to change" do
    redirect = OpenBlog::Redirect.create!(old_path: "/blog/old", new_path: "/blog/example", source: "manual", occurred_on: Date.current, post: @post)
    redirect.update!(new_path: "/blog/new")
    refute redirect.update(old_path: "/blog/replacement")
    assert_equal "/blog/old", redirect.reload.old_path
  end
end

class ImageAttachmentCommitTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "file attachment creation commits and metadata analysis can finish" do
    bytes = SecureRandom.hex(16)
    image = OpenBlog::Image.create!(sha256: Digest::SHA256.hexdigest(bytes), filename: "image.png", content_type: "image/png", byte_size: bytes.bytesize,
      file: { io: StringIO.new(bytes), filename: "image.png", content_type: "image/png" })
    blob = image.file.blob
    blob.update!(metadata: blob.metadata.merge(analyzed: true, width: 1, height: 1))
    assert_equal bytes, image.reload.file.download
    assert image.readonly?
  ensure
    if image&.persisted?
      ActiveStorage::Attachment.where(record: image).delete_all
      OpenBlog::Image.where(id: image.id).delete_all
    end
    blob&.purge
  end
end

class ImageAttachmentProtectionTest < ActiveSupport::TestCase
  setup do
    @image = OpenBlog::Image.create!(sha256: Digest::SHA256.hexdigest("image"), filename: "image.png", content_type: "image/png", byte_size: 5,
      file: { io: StringIO.new("image"), filename: "image.png", content_type: "image/png" })
    @replacement = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("replacement"), filename: "replacement.png")
  end

  teardown do
    @image.file.blob.service.delete(@image.file.blob.key)
    @replacement.service.delete(@replacement.key)
  end

  test "direct attachment updates cannot replace or reparent image bytes" do
    attachment = @image.file_attachment
    assert_raises(ActiveRecord::ReadOnlyRecord) { attachment.update!(blob: @replacement) }
    attachment.reload
    assert_raises(ActiveRecord::ReadOnlyRecord) { attachment.update_columns(blob_id: @replacement.id) }
    author = OpenBlog::Author.create!(name: "Reparent Target")
    assert_raises(ActiveRecord::ReadOnlyRecord) { attachment.update!(record: author) }
    assert_equal "image", @image.reload.file.download
  end

  test "direct attachment destruction cannot detach image bytes" do
    %i[destroy! purge purge_later].each do |operation|
      assert_raises(ActiveRecord::ReadOnlyRecord) { @image.reload.file_attachment.public_send(operation) }
      assert @image.reload.file.attached?
    end
    assert_equal "image", @image.file.download
  end

  test "an extra attachment cannot be inserted for an existing image" do
    assert_raises(ActiveRecord::ReadOnlyRecord) do
      ActiveStorage::Attachment.create!(record: @image, name: "file", blob: @replacement)
    end
    assert_equal 1, ActiveStorage::Attachment.where(record: @image).count
  end

  test "an unrelated host attachment remains writable but cannot be moved to an image" do
    author = OpenBlog::Author.create!(name: "Avatar Owner", avatar: @replacement)
    attachment = author.avatar_attachment
    assert_raises(ActiveRecord::ReadOnlyRecord) { attachment.update_columns(record_type: "OpenBlog::Image", record_id: @image.id) }
    attachment.reload.update!(blob: @image.file.blob)
    assert_equal @image.file.blob, author.reload.avatar.blob
    author.avatar_attachment.destroy!
    refute author.reload.avatar.attached?
  end
end
