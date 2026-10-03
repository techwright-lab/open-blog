require_relative "test_helper"
require "minitest/mock"
require "zlib"

class ImageImportTest < ActiveSupport::TestCase
  setup do
    @limit = OpenBlog.config.max_image_bytes
    @types = OpenBlog.config.image_content_types
    @blobs = []
  end

  teardown do
    OpenBlog.config.max_image_bytes = @limit
    OpenBlog.config.image_content_types = @types
    @blobs.each { |blob| blob.service.delete(blob.key) }
  end

  test "preparation reads storage once and creates no database records or metadata" do
    blob = upload_png
    original_metadata = blob.metadata.dup
    counts = record_counts
    reads = 0
    original_download = blob.service.method(:download)
    prepared = nil
    blob.service.stub(:download, ->(*args, &block) { reads += 1; original_download.call(*args, &block) }) do
      prepared = OpenBlog::ImageImport.prepare(signed_id: blob.signed_id)
    end
    assert_equal 1, reads
    assert_equal counts, record_counts
    assert_equal original_metadata, blob.reload.metadata
    assert_equal Digest::SHA256.hexdigest(png_bytes), prepared.attributes[:sha256]
    assert_equal png_bytes.bytesize, prepared.attributes[:byte_size]
    assert_equal "image/png", prepared.attributes[:content_type]
    assert_equal [ 2, 3 ], prepared.attributes.values_at(:width, :height)
    assert prepared.image.new_record?
    assert_equal prepared.attributes[:sha256], prepared.image.sha256
  end

  test "persistence attaches the existing blob without another download or upload" do
    blob = upload_png
    prepared = OpenBlog::ImageImport.prepare(signed_id: blob.signed_id)
    before_blobs = ActiveStorage::Blob.count
    image = nil
    blob.service.stub(:download, ->(*) { flunk "unexpected second storage download" }) do
      blob.service.stub(:upload, ->(*) { flunk "unexpected duplicate storage upload" }) do
        image = prepared.persist(uploaded_by: "importer")
      end
    end
    assert_equal before_blobs, ActiveStorage::Blob.count
    assert_equal blob.id, image.file.blob.id
    assert_equal "importer", image.uploaded_by
    assert_equal [ 2, 3 ], [ image.width, image.height ]
    assert_equal Digest::SHA256.hexdigest(png_bytes), image.sha256
    assert blob.reload.analyzed?
    assert image.readonly?
  end

  test "a rollback preserves the original blob without image attachment or metadata changes" do
    blob = upload_png
    original_metadata = blob.metadata.dup
    prepared = OpenBlog::ImageImport.prepare(signed_id: blob.signed_id)
    counts = record_counts
    OpenBlog::Image.transaction do
      prepared.persist(uploaded_by: "importer")
      raise ActiveRecord::Rollback
    end
    assert_equal counts, record_counts
    assert_equal original_metadata, blob.reload.metadata
    assert_equal png_bytes, blob.download
  end

  test "digest reuse retains the existing image path and its original blob" do
    first = upload_png(filename: "original.png")
    original = OpenBlog::ImageImport.prepare(signed_id: first.signed_id).persist
    second = upload_png(filename: "renamed.png")
    prepared = OpenBlog::ImageImport.prepare("signed_id" => second.signed_id)
    assert_equal original, prepared.image
    assert_equal original.path, prepared.image.path
    assert_no_difference [ "OpenBlog::Image.count", "ActiveStorage::Attachment.count", "ActiveStorage::Blob.count" ] do
      assert_equal original, prepared.persist
    end
    assert_equal first.id, original.file.blob.id
  end

  test "persistence refuses a blob whose source metadata changed after preparation" do
    blob = upload_png
    prepared = OpenBlog::ImageImport.prepare(signed_id: blob.signed_id)
    blob.update_columns(content_type: "text/plain")
    assert_no_difference [ "OpenBlog::Image.count", "ActiveStorage::Attachment.count" ] do
      assert_raises(OpenBlog::Error::ImageNotPermitted) { prepared.persist }
    end
  end

  test "invalid signed references and unsupported inputs are typed refusals" do
    [ nil, {}, { signed_id: "invalid" }, { signed_id: nil }, { signed_id: "", extra: true } ].each do |input|
      assert_raises(OpenBlog::Error::ImageNotPermitted) { OpenBlog::ImageImport.prepare(input) }
    end
  end

  test "declared and actual content must be permitted images with valid dimensions" do
    wrong_type = upload_png(content_type: "text/plain")
    assert_raises(OpenBlog::Error::ImageNotPermitted) { OpenBlog::ImageImport.prepare(signed_id: wrong_type.signed_id) }
    fake = upload("ordinary text", filename: "fake.png", content_type: "image/png")
    assert_raises(OpenBlog::Error::ImageNotPermitted) { OpenBlog::ImageImport.prepare(signed_id: fake.signed_id) }
    truncated = upload(png_bytes[0, 32], filename: "truncated.png", content_type: "image/png")
    assert_raises(OpenBlog::Error::ImageNotPermitted) { OpenBlog::ImageImport.prepare(signed_id: truncated.signed_id) }
    OpenBlog.config.image_content_types = [ "image/jpeg" ]
    assert_raises(OpenBlog::Error::ImageNotPermitted) { OpenBlog::ImageImport.prepare(signed_id: upload_png.signed_id) }
    assert_equal 0, OpenBlog::Image.count
  end

  test "size limits are checked before reads and while reading actual bytes" do
    blob = upload_png
    OpenBlog.config.max_image_bytes = blob.byte_size - 1
    blob.service.stub(:download, ->(*) { flunk "oversized metadata should refuse before download" }) do
      assert_raises(OpenBlog::Error::ImageNotPermitted) { OpenBlog::ImageImport.prepare(signed_id: blob.signed_id) }
    end
    blob.update_columns(byte_size: 1)
    assert_raises(OpenBlog::Error::ImageNotPermitted) { OpenBlog::ImageImport.prepare(signed_id: blob.signed_id) }
  end

  test "missing storage and changed bytes return typed image refusals" do
    missing = upload_png
    missing.service.delete(missing.key)
    assert_raises(OpenBlog::Error::ImageNotPermitted) { OpenBlog::ImageImport.prepare(signed_id: missing.signed_id) }
    changed = upload_png
    changed.update_columns(checksum: Base64.strict_encode64("x" * 16))
    assert_raises(OpenBlog::Error::ImageNotPermitted) { OpenBlog::ImageImport.prepare(signed_id: changed.signed_id) }
  end

  private

  def record_counts
    [ OpenBlog::Image.count, ActiveStorage::Blob.count, ActiveStorage::Attachment.count ]
  end

  def upload_png(**attributes)
    upload(png_bytes, **{ filename: "seedling.png", content_type: "image/png" }.merge(attributes))
  end

  def upload(bytes, **attributes)
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new(bytes), identify: false, **attributes).tap { |blob| @blobs << blob }
  end

  def png_bytes
    "\x89PNG\r\n\x1a\n".b + png_chunk("IHDR", [ 2, 3, 8, 2, 0, 0, 0 ].pack("NNC5")) +
      png_chunk("IDAT", Zlib::Deflate.deflate(("\0".b + "\x12\x34\x56".b * 2) * 3)) + png_chunk("IEND", "".b)
  end

  def png_chunk(type, data)
    [ data.bytesize ].pack("N") + type + data + [ Zlib.crc32(type + data) ].pack("N")
  end
end
