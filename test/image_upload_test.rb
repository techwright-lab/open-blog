require_relative "test_helper"
require "minitest/mock"
require "zlib"

class ImageUploadTest < ActiveSupport::TestCase
  setup do
    @limit = OpenBlog.config.max_image_bytes
  end
  teardown { OpenBlog.config.max_image_bytes = @limit }

  test "upload preparation decodes immutable bounded bytes without writing" do
    bytes = png
    io = StringIO.new(bytes)
    before = counts
    prepared = OpenBlog::ImageImport.prepare_upload(io, filename: "garden.png", content_type: "image/png")
    assert_equal before, counts
    assert_equal Digest::SHA256.hexdigest(bytes), prepared.attributes[:sha256]
    assert_equal [ 3, 2 ], prepared.attributes.values_at(:width, :height)
    assert prepared.image.new_record?
    io.string.replace("changed")
    image = prepared.persist(uploaded_by: "Photographer")
    assert_equal "Photographer", image.uploaded_by
    assert_equal prepared.attributes[:sha256], image.sha256
    assert image.file.attached?
    assert image.file.blob.analyzed?
  end

  test "upload rollback leaves no rows or storage upload" do
    prepared = OpenBlog::ImageImport.prepare_upload(StringIO.new(png), filename: "garden.png", content_type: "image/png")
    before = counts
    service.stub(:upload, ->(*) { flunk "must not upload before outer commit" }) do
      OpenBlog::Image.transaction(requires_new: true) do
        image = prepared.persist
        assert image.persisted?
        assert image.file.blob.persisted?
        raise ActiveRecord::Rollback
      end
    end
    assert_equal before, counts
  end

  test "identical upload bytes retain first filename and blob without duplicates" do
    first = OpenBlog::Image.from_upload(StringIO.new(png), filename: "first.png", content_type: "image/png", uploaded_by: "First")
    before = counts
    second = OpenBlog::Image.from_upload(StringIO.new(png), filename: "second.png", content_type: "image/png", uploaded_by: "Second")
    assert_equal first, second
    assert_equal "first.png", second.filename
    assert_equal "First", second.uploaded_by
    assert_equal first.file.blob, second.file.blob
    assert_equal before, counts
  end

  test "upload inputs reject size mismatch magic unsupported types and undecodable bytes" do
    [ [ "<svg xmlns='http://www.w3.org/2000/svg'/>", "image/svg+xml" ], [ "<html>fake</html>", "image/png" ],
      [ png[0, 32], "image/png" ], [ png, "image/jpeg" ] ].each do |bytes, type|
      assert_raises(OpenBlog::Error::ImageNotPermitted) do
        OpenBlog::ImageImport.prepare_upload(StringIO.new(bytes), filename: "input.png", content_type: type)
      end
    end
    OpenBlog.config.max_image_bytes = 10
    source = StringIO.new(png)
    assert_raises(OpenBlog::Error::ImageNotPermitted) do
      OpenBlog::ImageImport.prepare_upload(source, filename: "input.png", content_type: "image/png")
    end
    assert_operator source.pos, :<=, 11
    assert_equal [ 0, 0, 0 ], counts
  end

  test "URL preparation uses fetch policy closes its IO and records source without writes" do
    source = StringIO.new(png)
    before = counts
    arguments = nil
    fetch = ->(url, **options) { arguments = [ url, options ]; { io: source, content_type: "image/png", filename: "remote.png" } }
    OpenBlog::ImageFetch.stub(:call, fetch) do
      prepared = OpenBlog::ImageImport.prepare(url: "https://images.example/remote.png")
      assert_equal before, counts
      assert source.closed?
      assert_equal "https://images.example/remote.png", prepared.attributes[:source_url]
      assert_equal "https://images.example/remote.png", arguments.first
      assert_equal OpenBlog.config.max_image_bytes, arguments.last[:max_bytes]
      assert_equal OpenBlog.config.image_fetch_policy, arguments.last[:policy]
    end
  end

  test "signed image wrapper retains the host blob and typed invalid inputs" do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(png), filename: "host.png", content_type: "image/png", identify: false)
    image = OpenBlog::Image.from_signed_id(blob.signed_id, uploaded_by: "Host")
    assert_equal blob, image.file.blob
    assert_equal "Host", image.uploaded_by
    assert_raises(OpenBlog::Error::ImageNotPermitted) { OpenBlog::Image.from_signed_id("invalid") }
  ensure
    blob&.service&.delete(blob.key) if blob
  end

  test "upload filenames containing NUL are typed refusals" do
    assert_raises(OpenBlog::Error::ImageNotPermitted) do
      OpenBlog::ImageImport.prepare_upload(StringIO.new(png), filename: "bad\0.png", content_type: "image/png")
    end
    assert_equal [ 0, 0, 0 ], counts
  end

  private

  def counts
    [ OpenBlog::Image.count, ActiveStorage::Blob.count, ActiveStorage::Attachment.count ]
  end

  def service
    ActiveStorage::Blob.services.fetch(OpenBlog.config.storage_service || Rails.application.config.active_storage.service)
  end

  def png
    "\x89PNG\r\n\x1a\n".b + chunk("IHDR", [ 3, 2, 8, 2, 0, 0, 0 ].pack("NNC5")) +
      chunk("IDAT", Zlib::Deflate.deflate(("\0".b + "\x12\x34\x56".b * 3) * 2)) + chunk("IEND", "".b)
  end

  def chunk(type, data)
    [ data.bytesize ].pack("N") + type + data + [ Zlib.crc32(type + data) ].pack("N")
  end
end
