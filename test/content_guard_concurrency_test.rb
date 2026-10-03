require_relative "test_helper"
require "timeout"

class ContentGuardConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    skip "Row locking is specific to PostgreSQL" unless OpenBlog::Post.connection.adapter_name == "PostgreSQL"
    @formats = OpenBlog.config.body_formats
    OpenBlog.config.body_formats = [ :markdown, :rich_text ]
    @author = OpenBlog::Author.create!(name: "Concurrent Gardener", slug: "gardener-#{SecureRandom.hex(6)}")
  end

  teardown do
    if @author
      ids = OpenBlog::Post.where(author: @author).pluck(:id)
      OpenBlog::Post.where(id: ids).update_all(public_revision_id: nil)
      [ OpenBlog::Approval, OpenBlog::Publication, OpenBlog::Baseline, OpenBlog::ConnectionDeclaration,
        OpenBlog::Revision, OpenBlog::Faq, OpenBlog::Tagging, OpenBlog::Redirect ].each do |model|
        model.where(post_id: ids).delete_all
      end
      ActionText::RichText.where(record_type: "OpenBlog::Post", record_id: ids).delete_all
      OpenBlog::Post.where(id: ids).delete_all
      @author.destroy!
      OpenBlog.config.body_formats = @formats
    end
  end

  test "a direct FAQ edit and stale parent save retain both changes and their releases" do
    post = create_post
    faq = post.faqs.create!(position: 1, question: "When?", answer: "At dawn.")
    before = post.publications.count
    race([
      -> { child = OpenBlog::Faq.find(faq.id); -> { child.update!(answer: "At sunset.") } },
      -> { parent = OpenBlog::Post.includes(:faqs).find(post.id); -> { parent.update!(title: "Evening watering") } }
    ])
    assert_equal "Evening watering", post.reload.title
    assert_equal "At sunset.", post.faqs.sole.answer
    assert_equal before + 2, post.publications.count
    assert_consistent(post)
  end

  test "simultaneous rich text and FAQ writes serialize into complete stored revisions" do
    post = create_post(body_format: "rich_text")
    post.rich_body.update!(body: "<p>Use clean water.</p>")
    faq = post.faqs.create!(position: 1, question: "When?", answer: "At dawn.")
    rich_id = post.rich_body.id
    before = post.publications.count
    race([
      -> { rich = ActionText::RichText.find(rich_id); -> { rich.update!(body: "<p>Collect rainwater.</p>") } },
      -> { child = OpenBlog::Faq.find(faq.id); -> { child.update!(answer: "At sunset.") } }
    ])
    assert_equal "<p>Collect rainwater.</p>", post.reload.body_for_payload
    assert_equal "At sunset.", post.faqs.sole.answer
    assert_equal before + 2, post.publications.count
    assert_consistent(post)
  end

  test "the parent lock is acquired before a direct child SQL update" do
    post = create_post
    faq = post.faqs.create!(position: 1, question: "When?", answer: "At dawn.")
    paused, resume = Queue.new, Queue.new
    worker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        child = OpenBlog::Faq.find(faq.id)
        child.singleton_class.prepend(Module.new do
          define_method(:_update_record) do |*arguments|
            paused << true
            resume.pop
            super(*arguments)
          end
        end)
        child.update!(answer: "At sunset.")
      end
    end
    worker.report_on_exception = false
    Timeout.timeout(5) { paused.pop }
    assert_raises(ActiveRecord::LockWaitTimeout) do
      OpenBlog::Post.transaction(requires_new: true) do
        OpenBlog::Post.connection.execute("SET LOCAL lock_timeout = '250ms'")
        OpenBlog::Post.find(post.id).update!(title: "A competing edit")
      end
    end
    resume << true
    await_threads([ worker ])
    assert_equal "At sunset.", faq.reload.answer
    assert_equal "Watering notes", post.reload.title
    assert_consistent(post)
  ensure
    resume << true if resume
    worker.kill if worker&.alive?
    worker&.join(1)
  end

  private

  def create_post(**attributes)
    OpenBlog::Post.create!({ title: "Watering notes", slug: "watering-#{SecureRandom.hex(6)}", body_markdown: "Water lightly.",
      author: @author, author_name: @author.name, status: "published" }.merge(attributes))
  end

  def race(loaders)
    ready, start = Queue.new, Queue.new
    threads = loaders.map do |loader|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          write = loader.call
          ready << true
          start.pop
          write.call
        end
      end.tap { |thread| thread.report_on_exception = false }
    end
    Timeout.timeout(5) { threads.length.times { ready.pop } }
    threads.length.times { start << true }
    await_threads(threads)
  ensure
    Array(threads).each { |thread| thread.kill if thread.alive? }
    Array(threads).each { |thread| thread.join(1) }
  end

  def await_threads(threads)
    threads.each { |thread| assert thread.join(5), "Concurrent content write timed out" }
    threads.each(&:value)
  end

  def assert_consistent(post)
    payload = OpenBlog::RevisionPayload.new(post.reload)
    assert_equal payload.identifier, post.current_revision_identifier
    assert_equal payload.identifier, post.public_revision.identifier
    assert_equal payload.to_json, post.public_revision.payload
    assert_equal 1, post.publications.where(entry_type: "first").count
  end
end
