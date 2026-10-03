require_relative "test_helper"
require "minitest/mock"

class AdoptionConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @author = OpenBlog::Author.create!(name: "Alex Orchard", slug: "alex-orchard-#{SecureRandom.hex(6)}")
    @source_id = SecureRandom.hex(10)
    @now = Time.utc(2026, 8, 10, 14)
  end

  teardown do
    ids = OpenBlog::Post.where(author: @author).pluck(:id)
    OpenBlog::Post.where(id: ids).update_all(public_revision_id: nil)
    [ OpenBlog::Approval, OpenBlog::Publication, OpenBlog::Baseline, OpenBlog::ConnectionDeclaration,
      OpenBlog::Revision, OpenBlog::Faq, OpenBlog::Tagging, OpenBlog::Redirect ].each do |model|
      model.where(post_id: ids).delete_all
    end
    ActionText::RichText.where(record_type: "OpenBlog::Post", record_id: ids).delete_all
    OpenBlog::Post.where(id: ids).delete_all
    @author.destroy!
  end

  test "concurrent source identity claims cannot create separate posts for different slugs" do
    skip "Concurrent source identity claims require PostgreSQL" unless OpenBlog::Post.connection.adapter_name == "PostgreSQL"
    ready, start = Queue.new, Queue.new
    finder = OpenBlog::Baseline.method(:find_by)
    lookup = lambda do |*arguments|
      baseline = finder.call(*arguments)
      if arguments.first.is_a?(Hash) && arguments.first[:source_id] == @source_id && baseline.nil?
        ready << true
        start.pop
      end
      baseline
    end
    results = nil
    OpenBlog::Baseline.stub(:find_by, lookup) do
      threads = 2.times.map do |index|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            OpenBlog::Adopt.call({ source_system: "parallel_archive", source_id: @source_id,
              slug: "source-#{@source_id}-#{index}", title: "Orchard journal", body_format: "markdown",
              body: "A record from the previous journal.", author: @author.id }, actor: "archivist", now: @now)
          end
        end
      end
      2.times { ready.pop }
      2.times { start << true }
      results = threads.map(&:value)
    end
    assert_equal 1, results.count(&:success?)
    assert_equal [ :identity_conflict ], results.reject(&:success?).map { |result| result.error.code }
    assert_equal 1, OpenBlog::Post.where(author: @author).count
    assert_equal 1, OpenBlog::Baseline.where(source_system: "parallel_archive", source_id: @source_id).count
    post = OpenBlog::Post.find_by!(author: @author)
    assert_equal 1, post.revisions.count
    assert_equal [ "adopted" ], post.publications.pluck(:entry_type)
    assert_equal OpenBlog::RevisionPayload.new(post).identifier, post.public_revision.identifier
  end
end
