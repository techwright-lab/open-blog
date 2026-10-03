require_relative "test_helper"
require "minitest/mock"
require "zlib"

class ImageUploadCommitTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    pixel = SecureRandom.random_bytes(3)
    @bytes = "\x89PNG\r\n\x1a\n".b + chunk("IHDR", [ 2, 2, 8, 2, 0, 0, 0 ].pack("NNC5")) +
      chunk("IDAT", Zlib::Deflate.deflate(("\0".b + pixel * 2) * 2)) + chunk("IEND", "".b)
    @sha = Digest::SHA256.hexdigest(@bytes)
    @keys = []
  end

  teardown do
    images = OpenBlog::Image.where(sha256: @sha)
    blobs = ActiveStorage::Blob.joins(:attachments).where(active_storage_attachments: { record_type: "OpenBlog::Image", record_id: images.select(:id) }).to_a
    ActiveStorage::Attachment.where(record_type: "OpenBlog::Image", record_id: images.select(:id)).delete_all
    images.delete_all
    blobs.each(&:purge)
    @keys.each { |key| service.delete(key) }
  end

  test "upload occurs once only after the outermost transaction commits" do
    uploads = []
    uploader = service.method(:upload)
    image = nil
    service.stub(:upload, ->(key, io, **options) { uploads << key; @keys << key; uploader.call(key, io, **options) }) do
      OpenBlog::Image.transaction do
        image = OpenBlog::Image.from_upload(StringIO.new(@bytes), filename: "committed.png", content_type: "image/png")
        assert_empty uploads
        refute service.exist?(image.file.blob.key)
      end
      assert_equal [ image.file.blob.key ], uploads
      assert_equal @bytes, image.file.download
      duplicate = OpenBlog::Image.from_upload(StringIO.new(@bytes), filename: "other.png", content_type: "image/png")
      assert_equal image, duplicate
      assert_equal 1, uploads.size
    end
  end

  test "outer rollback cancels upload and leaves no image blob or attachment" do
    before = [ OpenBlog::Image.count, ActiveStorage::Blob.count, ActiveStorage::Attachment.count ]
    service.stub(:upload, ->(*) { flunk "rolled back bytes reached storage" }) do
      OpenBlog::Image.transaction do
        OpenBlog::Image.from_upload(StringIO.new(@bytes), filename: "rolled-back.png", content_type: "image/png")
        raise ActiveRecord::Rollback
      end
    end
    assert_equal before, [ OpenBlog::Image.count, ActiveStorage::Blob.count, ActiveStorage::Attachment.count ]
  end

  test "simultaneous equal uploads keep one image blob and upload" do
    skip "Concurrent uploads require PostgreSQL" unless OpenBlog::Image.connection.adapter_name == "PostgreSQL"
    prepared = 2.times.map { |i| OpenBlog::ImageImport.prepare_upload(StringIO.new(@bytes), filename: "racing-#{i}.png", content_type: "image/png") }
    ready, start = Queue.new, Queue.new
    finder = OpenBlog::Image.method(:find_by)
    mutex, seen, uploads = Mutex.new, [], []
    lookup = lambda do |*arguments|
      record = finder.call(*arguments)
      first = mutex.synchronize do
        fresh = !seen.include?(Thread.current)
        seen << Thread.current if fresh
        fresh
      end
      if first && record.nil?
        ready << true
        start.pop
      end
      record
    end
    uploader = service.method(:upload)
    upload = ->(key, io, **options) { mutex.synchronize { uploads << key; @keys << key }; uploader.call(key, io, **options) }
    before = [ ActiveStorage::Blob.count, ActiveStorage::Attachment.count ]
    results = service.stub(:upload, upload) do
      OpenBlog::Image.stub(:find_by, lookup) do
        threads = prepared.map do |candidate|
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection { candidate.persist(uploaded_by: "Concurrent") }
          end
        end
        2.times { ready.pop }
        2.times { start << true }
        threads.map(&:value)
      end
    end
    assert_equal 1, results.map(&:id).uniq.size
    assert_equal 1, OpenBlog::Image.where(sha256: @sha).count
    after = ActiveRecord::Base.uncached { [ ActiveStorage::Blob.count, ActiveStorage::Attachment.count ] }
    assert_equal [ before[0] + 1, before[1] + 1 ], after
    assert_equal 1, uploads.size
    assert_equal @bytes, results.first.file.download
  end

  private

  def service
    ActiveStorage::Blob.services.fetch(OpenBlog.config.storage_service || Rails.application.config.active_storage.service)
  end

  def chunk(type, data)
    [ data.bytesize ].pack("N") + type + data + [ Zlib.crc32(type + data) ].pack("N")
  end
end
