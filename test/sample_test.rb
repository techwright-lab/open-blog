require_relative "test_helper"
require "minitest/mock"

class SampleTest < ActiveSupport::TestCase
  setup do
    @configuration = OpenBlog.config
    @settings = %i[body_formats default_body_format require_approval].to_h { |key| [ key, @configuration.public_send(key) ] }
    @blob_ids = ActiveStorage::Blob.pluck(:id)
  end

  teardown do
    ActiveStorage::Blob.where.not(id: @blob_ids).each { |blob| blob.service.delete(blob.key) }
    @settings.each { |key, value| @configuration.public_send("#{key}=", value) }
  end

  test "sample publishes original content with image, two FAQs and an honest AI label" do
    post = OpenBlog::Sample.call
    assert post.published?
    assert_equal "open_blog_sample", post.external_id
    assert_equal "General", post.category.name
    assert_equal OpenBlog.config.default_author[:name], post.author.name
    assert_equal "ai_assisted", post.provenance
    assert_equal :ai_assisted, OpenBlog::LabelPolicy.for(post)
    assert_empty post.approvals
    assert_equal 2, post.faqs.count
    assert post.cover_image.file.attached?
    assert_equal [ 1200, 630 ], [ post.cover_image.width, post.cover_image.height ]
    assert_equal 1, post.revisions.count
    document = Nokogiri::HTML5.fragment(OpenBlog::Renderer.render(post))
    %w[h2 h3 strong em del ul ol blockquote table pre code img figcaption br input[type=checkbox][disabled]].each do |selector|
      assert document.at_css(selector), "Missing sample feature #{selector}"
    end
    assert document.at_css('a[href^="#"]'), "Missing a local reference"
    assert document.at_css("img[alt]")["src"].start_with?(OpenBlog.mount_path)
  end

  test "repeated sample calls preserve existing sample and create no rows or uploads" do
    post = OpenBlog::Sample.call
    edited = OpenBlog::Publish.call({ title: "My own introduction", body: "A replacement article.", change: "substantive" }, post: post, actor: "Editor")
    assert edited.success?, edited.error&.message
    post = edited.post.reload
    models = [ OpenBlog::Post, OpenBlog::Author, OpenBlog::Category, OpenBlog::Image,
      OpenBlog::Revision, OpenBlog::Publication, OpenBlog::Faq, ActiveStorage::Blob, ActiveStorage::Attachment ]
    counts = models.map(&:count)
    ActiveStorage::Blob.stub(:create_and_upload!, ->(*) { flunk "sample uploaded another file" }) do
      assert_equal post.id, OpenBlog::Sample.call.id
    end
    assert_equal counts, models.map(&:count)
    assert_equal post.attributes, post.reload.attributes
  end

  test "rich text only installations receive a rendered sample with the same structured FAQ" do
    @configuration.body_formats = [ :rich_text ]
    @configuration.default_body_format = :rich_text
    post = OpenBlog::Sample.call
    assert post.rich_text?
    assert post.rich_body.present?
    document = Nokogiri::HTML5.fragment(OpenBlog::Renderer.render(post))
    %w[h2 table pre img].each { |selector| assert document.at_css(selector), selector }
    document.css('a[href^="#"]').each do |link|
      assert document.at_css("[id='#{link['href'].delete_prefix('#')}']"), "Broken sample reference #{link['href']}"
    end
    assert_equal 2, post.faqs.count
    assert_equal :ai_assisted, OpenBlog::LabelPolicy.for(post)
  end

  test "sample reuses the configured author and a preexisting General category" do
    author = OpenBlog::Author.create!(name: OpenBlog.config.default_author[:name])
    category = OpenBlog::Category.create!(name: "General")
    assert_no_difference [ "OpenBlog::Author.count", "OpenBlog::Category.count" ] do
      post = OpenBlog::Sample.call
      assert_equal author, post.author
      assert_equal category, post.category
    end
  end

  test "publication refusal rolls back sample rows and cleans up the uploaded file" do
    @configuration.require_approval = true
    counts = [ OpenBlog::Post, OpenBlog::Author, OpenBlog::Category, OpenBlog::Image, ActiveStorage::Blob ].map(&:count)
    deleted = []
    service = ActiveStorage::Blob.service
    original_delete = service.method(:delete)
    service.stub(:delete, ->(key) { deleted << key; original_delete.call(key) }) do
      assert_raises(OpenBlog::Error) { OpenBlog::Sample.call }
    end
    assert_equal 1, deleted.size
    refute service.exist?(deleted.first)
    assert_equal counts, [ OpenBlog::Post, OpenBlog::Author, OpenBlog::Category, OpenBlog::Image, ActiveStorage::Blob ].map(&:count)
  end

  test "an unrelated article with the sample slug is never replaced" do
    existing = OpenBlog::SaveDraft.call({ title: "My introduction", slug: "open-blog-sample", body: "Keep this article." }, actor: "Editor").post
    assert_raises(OpenBlog::Error::IdentityConflict) { OpenBlog::Sample.call }
    assert_nil existing.reload.external_id
    assert_equal "Keep this article.", existing.body_markdown
    assert existing.draft?
  end
end
