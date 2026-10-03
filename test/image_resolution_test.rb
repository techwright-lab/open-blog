require_relative "test_helper"
require "minitest/mock"
require "zlib"

class ImageResolutionTest < ActiveSupport::TestCase
  setup do
    @author = OpenBlog::Author.create!(name: "Morgan Reed", slug: "morgan-reed")
    @blobs = []
    @formats = OpenBlog.config.body_formats
    OpenBlog.config.body_formats = %i[markdown rich_text]
    @hook = OpenBlog.config.before_publish
  end

  teardown do
    OpenBlog.config.before_publish = @hook
    OpenBlog.config.body_formats = @formats
    @blobs.each { |blob| blob.service.delete(blob.key) }
  end

  test "external image digests survive fresh reads FAQ saves and metadata updates" do
    result = nil
    OpenBlog::ImageResolution.stub(:fetch_external, "a" * 64) do
      result = publish(body: "![A meadow](https://images.example/meadow.png)")
    end
    assert result.success?, result.error&.message
    post = result.post.reload
    expected = [ { "url" => "https://images.example/meadow.png", "sha256" => "a" * 64, "alt" => "A meadow", "role" => "body" } ]
    assert_equal expected, OpenBlog::RevisionPayload.new(post).to_h.fetch("images")
    OpenBlog::ImageResolution.stub(:fetch_external, ->(*) { flunk "unchanged content must not refetch" }) do
      post.faqs.create!(question: "When do flowers bloom?", answer: "In spring.", position: 1)
      changed = OpenBlog::Publish.call({ featured: true }, post: post, actor: "editor")
      assert changed.success?, changed.error&.message
      assert_equal expected, JSON.parse(changed.post.public_revision.payload).fetch("images")
      assert_equal expected, OpenBlog::RevisionPayload.new(changed.post.reload).to_h.fetch("images")
    end
  end

  test "new direct external content does not reuse a prior digest" do
    result = nil
    OpenBlog::ImageResolution.stub(:fetch_external, "a" * 64) { result = publish(body: "![Grass](https://images.example/grass.png)") }
    post = result.post
    OpenBlog::ImageResolution.stub(:fetch_external, ->(*) { flunk "native saves must not fetch external URLs" }) do
      post.update!(body_markdown: "![Flowers](https://images.example/flowers.png)")
    end
    entry = JSON.parse(post.reload.public_revision.payload).fetch("images").sole
    assert_equal "https://images.example/flowers.png", entry.fetch("url")
    assert_equal "", entry.fetch("sha256")
    assert_equal post.current_revision_identifier, OpenBlog::RevisionPayload.new(post).identifier
  end

  test "preparation reads a blob before the operation transaction and imports before post save" do
    blob = upload_png
    depth = ActiveRecord::Base.connection.open_transactions
    reads = []
    downloader = blob.service.method(:download)
    result = nil
    blob.service.stub(:download, ->(*args, &block) { reads << ActiveRecord::Base.connection.open_transactions; downloader.call(*args, &block) }) do
      result = publish(body_format: "rich_text", body: attachment(blob))
    end
    assert result.success?, result.error&.message
    assert_equal [ depth ], reads
    image = OpenBlog::Image.sole
    assert_equal blob.id, image.file.blob.id
    post = result.post.reload
    entry = JSON.parse(post.public_revision.payload).fetch("images").sole
    assert_equal image.path, entry.fetch("url")
    assert_equal image.sha256, entry.fetch("sha256")
    assert_includes post.body_for_payload, "action-text-attachment"
    assert_equal post.current_revision_identifier, OpenBlog::RevisionPayload.new(post).identifier
  end

  test "a hook cannot introduce an unprepared image and leave imported rows" do
    blob = upload_png
    OpenBlog.config.before_publish = ->(post, _) { post.rich_body = '<p>Changed by host.</p><img src="https://images.example/new.png">'; nil }
    assert_no_difference [ "OpenBlog::Post.count", "OpenBlog::Image.count", "OpenBlog::Revision.count", "ActiveStorage::Attachment.count" ] do
      result = publish(body_format: "rich_text", body: attachment(blob))
      assert_equal :validation_failed, result.error&.code
      assert_includes result.error.details, "body"
    end
  end

  test "native rich text child writes import blobs and record exactly once atomically" do
    result = publish(body_format: "rich_text", body: "<p>Meadow notes.</p>")
    blob = upload_png
    assert_difference [ "OpenBlog::Image.count", "OpenBlog::Revision.count", "OpenBlog::Publication.count" ], 1 do
      result.post.rich_body.update!(body: attachment(blob))
    end
    post = result.post.reload
    assert_equal OpenBlog::Image.sole.path, JSON.parse(post.public_revision.payload).fetch("images").sole.fetch("url")
    assert_equal post.current_revision_identifier, OpenBlog::RevisionPayload.new(post).identifier
  end

  test "native blob import rolls back when release recording fails" do
    result = publish(body_format: "rich_text", body: "<p>Meadow notes.</p>")
    blob = upload_png
    before = result.post.body_for_payload
    metadata = blob.metadata.deep_dup
    OpenBlog::RecordRelease.stub(:call, ->(*) { raise "recording failed" }) do
      assert_no_difference [ "OpenBlog::Image.count", "ActiveStorage::Attachment.count" ] do
        assert_raises(RuntimeError) { result.post.rich_body.update!(body: attachment(blob)) }
      end
    end
    assert_equal before, result.post.reload.body_for_payload
    assert_equal metadata, blob.reload.metadata
  end

  test "adoption previews imported attachments without retaining image rows" do
    blob = upload_png
    result = nil
    assert_no_difference [ "OpenBlog::Post.count", "OpenBlog::Image.count", "ActiveStorage::Attachment.count" ] do
      result = OpenBlog::Adopt.call({ source_system: "field_notes", source_id: "meadow", slug: "meadow", title: "Meadow notes",
        body_format: "rich_text", body: attachment(blob), author: @author.id, dry_run: true }, actor: "importer")
      assert result.success?, result.error&.message
    end
    assert_equal Digest::SHA256.hexdigest(png_bytes), JSON.parse(result.post.public_revision.payload).fetch("images").sole.fetch("sha256")
    assert_includes result.post.body_for_payload, "action-text-attachment"
  end

  test "draft image metadata persists without a public revision" do
    result = nil
    OpenBlog::ImageResolution.stub(:fetch_external, "c" * 64) do
      result = OpenBlog::SaveDraft.call({ title: "Draft flowers", slug: "draft-flowers", author: @author.id,
        body: "![Flowers](https://images.example/flowers.png)" }, actor: "editor")
    end
    assert result.success?, result.error&.message
    assert_nil result.post.public_revision
    assert_equal "c" * 64, OpenBlog::RevisionPayload.new(result.post.reload).to_h.fetch("images").sole.fetch("sha256")
  end

  test "an operation returns a typed refusal when its selected post was deleted" do
    draft = OpenBlog::SaveDraft.call({ title: "Gone notes", slug: "gone-notes", author: @author.id }, actor: "editor").post
    OpenBlog::Post.where(id: draft.id).delete_all
    result = OpenBlog::SaveDraft.call({ featured: true }, post: draft, actor: "editor")
    assert_equal :not_found, result.error&.code
  end

  test "metadata preflight takes the newly locked body if another writer changed its images" do
    draft = OpenBlog::SaveDraft.call({ title: "Shared notes", slug: "shared-notes", author: @author.id,
      body: "![Grass](https://images.example/grass.png)" }, actor: "editor").post
    original = OpenBlog::ImageResolution.method(:prepare)
    prepare = ->(**arguments) do
      prepared = original.call(**arguments)
      OpenBlog::Post.find(draft.id).update!(body_markdown: "![Flowers](https://images.example/flowers.png)")
      prepared
    end
    result = nil
    OpenBlog::ImageResolution.stub(:prepare, prepare) do
      result = OpenBlog::SaveDraft.call({ featured: true }, post: draft, actor: "editor")
    end
    assert result.success?, result.error&.message
    assert result.post.featured?
    assert_equal "![Flowers](https://images.example/flowers.png)", result.post.reload.body_markdown
    assert_equal "https://images.example/flowers.png", OpenBlog::RevisionPayload.new(result.post).to_h.fetch("images").sole.fetch("url")
  end

  test "a hook may change text while keeping prepared images" do
    OpenBlog.config.before_publish = ->(post, _) { post.body_markdown += "\n\nAdded context."; nil }
    result = nil
    OpenBlog::ImageResolution.stub(:fetch_external, "b" * 64) do
      result = publish(body: "![Grass](https://images.example/grass.png)")
    end
    assert result.success?, result.error&.message
    assert_includes result.post.body_markdown, "Added context."
    assert_equal "b" * 64, JSON.parse(result.post.public_revision.payload).fetch("images").sole.fetch("sha256")
    assert_equal result.post.current_revision_identifier, OpenBlog::RevisionPayload.new(result.post.reload).identifier
  end

  test "served image paths and sanitized ordered payload entries agree" do
    image = OpenBlog::Image.create!(sha256: "d" * 64, filename: "actual.png", content_type: "image/png", byte_size: 5)
    result = publish(body_format: "rich_text", body: %(<img src="#{image.path.sub("actual.png", "different.png")}" alt="One"><img src="javascript:bad" alt="Unsafe"><img src="#{image.path}" alt="Two">))
    assert result.success?, result.error&.message
    served = Nokogiri::HTML5.fragment(OpenBlog::Renderer.render(result.post)).css("img").map { |node| [ node["src"], node["alt"] ] }
    entries = JSON.parse(result.post.public_revision.payload).fetch("images")
    assert_equal [ [ image.path, "One" ], [ image.path, "Two" ] ], served
    assert_equal served, entries.map { |entry| entry.values_at("url", "alt") }
  end

  test "images embedded in code are not recorded as served images" do
    result = publish(body_format: "rich_text", body: '<pre lang="ruby"><code><img src="https://images.example/fake.png">puts 1</code></pre>')
    assert result.success?, result.error&.message
    assert_empty JSON.parse(result.post.public_revision.payload).fetch("images")
    fragment = Nokogiri::HTML5.fragment(OpenBlog::Renderer.render(result.post))
    assert_nil fragment.at_css("img")
    assert_includes fragment.at_css("pre").text, "puts 1"
  end

  test "cover and social signed blobs are read before locking and share one image" do
    blob = upload_png
    depth = ActiveRecord::Base.connection.open_transactions
    reads = []
    downloader = blob.service.method(:download)
    result = nil
    blob.service.stub(:download, ->(*args, &block) { reads << ActiveRecord::Base.connection.open_transactions; downloader.call(*args, &block) }) do
      result = publish(cover_image: { signed_id: blob.signed_id }, social_image: { signed_id: blob.signed_id })
    end
    assert result.success?, result.error&.message
    assert reads.all? { |value| value == depth }
    assert_operator reads.length, :>=, 1
    assert_equal result.post.cover_image_id, result.post.social_image_id
    assert_equal 1, OpenBlog::Image.count
    assert_equal blob.id, result.post.cover_image.file.blob.id
    assert_equal result.post.current_revision_identifier, result.post.public_revision.identifier
  end

  test "rejected cover publication leaves the host blob and no imported image" do
    blob = upload_png
    OpenBlog.config.before_publish = ->(*) { [ "Wait for review" ] }
    assert_no_difference [ "OpenBlog::Post.count", "OpenBlog::Image.count", "ActiveStorage::Attachment.count" ] do
      result = publish(cover_image: { signed_id: blob.signed_id })
      assert_equal :refused_by_host, result.error&.code
    end
    assert blob.service.exist?(blob.key)
  end

  test "external body verification closes fetched bytes without creating an image" do
    stream = StringIO.new(png_bytes)
    result = nil
    OpenBlog::ImageFetch.stub(:call, { io: stream, content_type: "image/png", filename: "leaf.png" }) do
      assert_no_difference "OpenBlog::Image.count" do
        result = publish(body: "![Leaf](https://images.example/leaf.png)")
      end
    end
    assert result.success?, result.error&.message
    assert stream.closed?
    assert_equal "![Leaf](https://images.example/leaf.png)", result.post.body_markdown
    assert_equal Digest::SHA256.hexdigest(png_bytes), result.post.body_image_manifest.sole.fetch("sha256")
  end

  test "a refused external body image stays unverified without refusing the article" do
    OpenBlog::ImageFetch.stub(:call, ->(*) { raise OpenBlog::Error::ImageNotPermitted }) do
      result = publish(body: "![Leaf](https://images.example/leaf.png)")
      assert result.success?, result.error&.message
      assert_equal "", result.post.body_image_manifest.sole.fetch("sha256")
      assert_equal "![Leaf](https://images.example/leaf.png)", result.post.body_markdown
    end
  end

  test "URL cover refusal and adoption dry run retain no rows or stored bytes" do
    streams = []
    fetch = lambda do |*, **|
      stream = StringIO.new(png_bytes)
      streams << stream
      { io: stream, content_type: "image/png", filename: "garden.png" }
    end
    service = ActiveStorage::Blob.service
    service.stub(:upload, ->(*) { flunk "A refused or preview-only operation uploaded bytes" }) do
      OpenBlog::ImageFetch.stub(:call, fetch) do
        assert_no_difference [ "OpenBlog::Post.count", "OpenBlog::Image.count", "ActiveStorage::Blob.count", "ActiveStorage::Attachment.count" ] do
          OpenBlog.config.before_publish = ->(*) { [ "Not ready" ] }
          refused = publish(cover_image: { url: "https://images.example/garden.png" })
          assert_equal :refused_by_host, refused.error&.code
          OpenBlog.config.before_publish = nil
          preview = OpenBlog::Adopt.call({ source_system: "notes", source_id: "garden", slug: "garden-import", title: "Garden",
            body_format: "markdown", body: "Water the seedlings.", cover_image: { url: "https://images.example/garden.png" }, dry_run: true }, actor: "Importer")
          assert preview.success?, preview.error&.message
          assert_equal Digest::SHA256.hexdigest(png_bytes), preview.post.cover_image.sha256
        end
      end
    end
    assert_equal 2, streams.length
    assert streams.all?(&:closed?)
  end

  private

  def publish(**attributes)
    OpenBlog::Publish.call({ title: "Meadow notes", slug: "meadow-notes", author: @author.id,
      body_format: "markdown", body: "A meadow in spring." }.merge(attributes), actor: "editor")
  end

  def attachment(blob)
    %(<p>Meadow.</p><action-text-attachment sgid="#{blob.attachable_sgid}" content-type="image/png" caption="A meadow" filename="meadow.png"></action-text-attachment>)
  end

  def upload_png
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new(png_bytes), filename: "meadow.png", content_type: "image/png", identify: false).tap { |blob| @blobs << blob }
  end

  def png_bytes
    "\x89PNG\r\n\x1a\n".b + chunk("IHDR", [ 2, 2, 8, 2, 0, 0, 0 ].pack("NNC5")) +
      chunk("IDAT", Zlib::Deflate.deflate(("\0".b + "\x12\x34\x56".b * 2) * 2)) + chunk("IEND", "".b)
  end

  def chunk(type, data)
    [ data.bytesize ].pack("N") + type + data + [ Zlib.crc32(type + data) ].pack("N")
  end
end
