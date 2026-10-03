require_relative "test_helper"
require "minitest/mock"
require "zlib"

class ImageImportConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  teardown do
    blobs = [ @blob, @other_blob ].compact
    if blobs.any?
      ids = ActiveStorage::Attachment.where(blob_id: blobs.map(&:id), record_type: "OpenBlog::Image").pluck(:record_id)
      ActiveStorage::Attachment.where(blob_id: blobs.map(&:id)).delete_all
      OpenBlog::Image.where(id: ids).delete_all
      blobs.each(&:purge)
    end
  end

  test "simultaneous imports of one blob reuse the winning image after waiting for its lock" do
    skip "Concurrent blob imports require PostgreSQL" unless OpenBlog::Image.connection.adapter_name == "PostgreSQL"
    pixel = SecureRandom.random_bytes(3)
    bytes = "\x89PNG\r\n\x1a\n".b + chunk("IHDR", [ 2, 2, 8, 2, 0, 0, 0 ].pack("NNC5")) +
      chunk("IDAT", Zlib::Deflate.deflate(("\0".b + pixel * 2) * 2)) + chunk("IEND", "".b)
    @blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(bytes), filename: "parallel.png",
      content_type: "image/png", identify: false)
    prepared = 2.times.map { OpenBlog::ImageImport.prepare(signed_id: @blob.signed_id) }
    ready, start = Queue.new, Queue.new
    finder = OpenBlog::Image.method(:find_by)
    seen, mutex = [], Mutex.new
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
    results = OpenBlog::Image.stub(:find_by, lookup) do
      threads = prepared.map do |candidate|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            candidate.persist(uploaded_by: "Importer")
          rescue OpenBlog::Error => error
            error
          end
        end
      end
      2.times { ready.pop }
      2.times { start << true }
      threads.map(&:value)
    end
    assert results.all? { |result| result.is_a?(OpenBlog::Image) }, results.map(&:inspect).join("\n")
    assert_equal 1, results.map(&:id).uniq.size
    assert_equal 1, OpenBlog::Image.where(sha256: Digest::SHA256.hexdigest(bytes)).count
    assert_equal [ @blob.id ], results.map { |record| record.file.blob.id }.uniq
  end

  test "different blobs with equal bytes reuse an image committed before the second validation" do
    skip "Concurrent blob imports require PostgreSQL" unless OpenBlog::Image.connection.adapter_name == "PostgreSQL"
    pixel = SecureRandom.random_bytes(3)
    bytes = "\x89PNG\r\n\x1a\n".b + chunk("IHDR", [ 2, 2, 8, 2, 0, 0, 0 ].pack("NNC5")) +
      chunk("IDAT", Zlib::Deflate.deflate(("\0".b + pixel * 2) * 2)) + chunk("IEND", "".b)
    @blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(bytes), filename: "winner.png", content_type: "image/png", identify: false)
    @other_blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(bytes), filename: "second.png", content_type: "image/png", identify: false)
    original_metadata = @other_blob.metadata.deep_dup
    prepared = [ @blob, @other_blob ].map { |blob| OpenBlog::ImageImport.prepare(signed_id: blob.signed_id) }
    second_saving, first_finished = Queue.new, Queue.new
    creator = OpenBlog::Image.method(:new)
    builder = lambda do |*arguments, **options|
      record = creator.call(*arguments, **options)
      saver = record.method(:save!)
      record.define_singleton_method(:save!) do |*save_arguments, **save_options|
        if uploaded_by == "First"
          second_saving.pop
        else
          second_saving << true
          first_finished.pop
        end
        saver.call(*save_arguments, **save_options)
      end
      record
    end
    results = OpenBlog::Image.stub(:new, builder) do
      threads = prepared.each_with_index.map do |candidate, index|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            candidate.persist(uploaded_by: index.zero? ? "First" : "Second")
          rescue OpenBlog::Error => error
            error
          ensure
            first_finished << true if index.zero?
          end
        end
      end
      threads.map(&:value)
    end
    assert results.all? { |result| result.is_a?(OpenBlog::Image) }, results.map(&:inspect).join("\n")
    assert_equal 1, results.map(&:id).uniq.size
    assert_equal [ "winner.png" ], results.map(&:filename).uniq
    assert_equal [ @blob.id ], results.map { |record| record.file.blob.id }.uniq
    assert_equal original_metadata, @other_blob.reload.metadata
  end

  private

  def chunk(type, data)
    [ data.bytesize ].pack("N") + type + data + [ Zlib.crc32(type + data) ].pack("N")
  end
end
