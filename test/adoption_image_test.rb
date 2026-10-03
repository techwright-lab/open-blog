require_relative "test_helper"
require "minitest/mock"
require "zlib"

class AdoptionImageTest < ActiveSupport::TestCase
  setup do
    @author = OpenBlog::Author.create!(name: "Jamie Green", slug: "jamie-green")
    @now = Time.utc(2026, 8, 10, 14)
    @blobs = []
  end

  teardown do
    @blobs.each { |blob| blob.service.delete(blob.key) }
  end

  test "adoption attaches the signed blob and records its exact image identity" do
    blob = upload_png("orchard.png")
    reads = 0
    downloader = blob.service.method(:download)
    result = nil
    before_blobs = ActiveStorage::Blob.count
    blob.service.stub(:download, ->(*args, &block) { reads += 1; downloader.call(*args, &block) }) do
      blob.service.stub(:upload, ->(*) { flunk "adoption must reuse the uploaded blob" }) do
        result = adopt(cover_image: { signed_id: blob.signed_id }, cover_alt: "A small tree")
      end
    end
    assert result.success?, result.error&.message
    assert_equal 1, reads
    assert_equal before_blobs, ActiveStorage::Blob.count
    image = result.post.cover_image
    assert_equal blob.id, image.file.blob.id
    assert_equal [ 2, 2 ], [ image.width, image.height ]
    assert_equal "archivist", image.uploaded_by
    expected_digest = Digest::SHA256.hexdigest(png_bytes)
    payload = JSON.parse(result.post.public_revision.payload)
    assert_equal expected_digest, payload.fetch("images").sole.fetch("sha256")
    assert_equal image.path, payload.fetch("images").sole.fetch("url")
    assert_equal "A small tree", payload.fetch("images").sole.fetch("alt")
    assert_equal OpenBlog::RevisionPayload.new(result.post.reload).identifier, result.post.public_revision.identifier
  end

  test "dry run leaves image attachments blob metadata and all adoption records unchanged" do
    blob = upload_png("preview.png")
    original_metadata = blob.metadata.deep_dup
    before = counts
    result = nil
    blob.service.stub(:upload, ->(*) { flunk "dry run must not write storage" }) do
      result = adopt(cover_image: { signed_id: blob.signed_id }, dry_run: true)
    end
    assert result.success?, result.error&.message
    assert result.dry_run
    assert_equal before, counts
    assert_equal original_metadata, blob.reload.metadata
    assert_equal png_bytes, blob.download
    assert_nil OpenBlog::Post.find_by(slug: "orchard-history")
  end

  test "a refused replacement reads but never persists its new image" do
    initial = adopt
    assert initial.success?, initial.error&.message
    changed = OpenBlog::Publish.call({ body: "New editorial advice.", change: "substantive" }, post: initial.post,
      actor: "editor", now: @now + 3600)
    assert changed.success?, changed.error&.message
    blob = upload_png("refused.png")
    original_metadata = blob.metadata.deep_dup
    before = counts
    result = adopt(cover_image: { signed_id: blob.signed_id })
    assert_equal :already_changed_in_gem, result.error.code
    assert_equal before, counts
    assert_equal original_metadata, blob.reload.metadata
    assert_nil initial.post.reload.cover_image
  end

  test "deduplicated images preserve the stored filename during adoption and repeat" do
    first_blob = upload_png("first.png")
    first_image = OpenBlog::ImageImport.prepare(signed_id: first_blob.signed_id).persist(uploaded_by: "previous importer")
    second_blob = upload_png("alternate.png")
    result = adopt(social_image: { signed_id: second_blob.signed_id })
    assert result.success?, result.error&.message
    assert_equal first_image, result.post.social_image
    assert_equal first_blob.id, result.post.social_image.file.blob.id
    before = counts
    repeat = adopt(social_image: { signed_id: second_blob.signed_id })
    assert repeat.success?, repeat.error&.message
    assert_nil repeat.records[:publication]
    assert_equal before, counts
    assert_equal first_image.path, JSON.parse(repeat.post.public_revision.payload).fetch("images").sole.fetch("url")
  end

  private

  def adopt(**attributes)
    OpenBlog::Adopt.call({ source_system: "journal_archive", source_id: "orchard-12", slug: "orchard-history",
      title: "Orchard history", body_format: "markdown", body: "Young trees need steady care.", author: @author.id }.merge(attributes),
      actor: "archivist", now: @now)
  end

  def counts
    [ OpenBlog::Post, OpenBlog::Author, OpenBlog::Category, OpenBlog::Tag, OpenBlog::Tagging, OpenBlog::Faq,
      OpenBlog::Revision, OpenBlog::Approval, OpenBlog::Publication, OpenBlog::Baseline,
      OpenBlog::ConnectionDeclaration, OpenBlog::Redirect, OpenBlog::Image,
      ActiveStorage::Blob, ActiveStorage::Attachment, ActionText::RichText ].map(&:count)
  end

  def upload_png(filename)
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new(png_bytes), filename: filename,
      content_type: "image/png", identify: false).tap { |blob| @blobs << blob }
  end

  def png_bytes
    "\x89PNG\r\n\x1a\n".b + chunk("IHDR", [ 2, 2, 8, 2, 0, 0, 0 ].pack("NNC5")) +
      chunk("IDAT", Zlib::Deflate.deflate(("\0".b + "\x45\x67\x89".b * 2) * 2)) + chunk("IEND", "".b)
  end

  def chunk(type, data)
    [ data.bytesize ].pack("N") + type + data + [ Zlib.crc32(type + data) ].pack("N")
  end
end
