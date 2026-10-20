require_relative "test_helper"
require "tempfile"

class RecordKeysTest < ActionDispatch::IntegrationTest
  setup do
    @hook = OpenBlog.config.authenticate
    OpenBlog.config.authenticate = ->(_) { OpenBlog::Actor.new(name: "Image editor") }
    @blob_ids = ActiveStorage::Blob.pluck(:id)
  end

  teardown do
    OpenBlog.config.authenticate = @hook
    ActiveStorage::Blob.where.not(id: @blob_ids).each { |blob| blob.service.delete(blob.key) }
  end

  test "blog image and author keys and their post references follow the attachment record key" do
    expected = ActiveStorage::Attachment.type_for_attribute("record_id").type
    assert_equal expected, OpenBlog::Image.type_for_attribute("id").type
    assert_equal expected, OpenBlog::Author.type_for_attribute("id").type
    %w[author_id cover_image_id social_image_id].each do |column|
      assert_equal expected, OpenBlog::Post.type_for_attribute(column).type, column
    end
    assert_equal :integer, OpenBlog::Post.type_for_attribute("id").type
  end

  test "uploaded images, author avatars and the sample attach on this host" do
    file = Tempfile.new([ "card", ".png" ], binmode: true)
    file.write(File.binread(OpenBlog::Engine.root.join("lib/generators/open_blog/install/templates/sample_cover.png")))
    file.rewind
    post "/blog/api/v1/images", params: { file: Rack::Test::UploadedFile.new(file.path, "image/png") }
    assert_response :created
    image = OpenBlog::Image.find(response.parsed_body.fetch("image_id"))
    assert_equal image.id, image.file.attachment.record_id

    post "/blog/api/v1/authors", params: { name: "Avery Stone", avatar: { image_id: image.id } }, as: :json
    assert_response :created
    author = OpenBlog::Author.find(response.parsed_body.fetch("id"))
    assert_equal author.id, author.avatar.attachment.record_id
    assert_equal image.sha256, response.parsed_body.dig("avatar", "sha256")

    sample = OpenBlog::Sample.call
    assert sample.cover_image.file.attached?
    assert_equal sample.cover_image.id, sample.cover_image.file.attachment.record_id
  ensure
    file&.close!
  end

  test "image identifiers in the API and MCP schema use the host key type" do
    image = OpenBlog::Image.create!(sha256: "c" * 64, filename: "c.png", content_type: "image/png", byte_size: 1)
    post "/blog/api/v1/posts", params: { title: "Keyed cover", body: "Text.", cover_image: { image_id: image.id } }, as: :json
    assert_response :created
    assert_equal image.id, response.parsed_body.dig("post", "cover_image", "image_id")
    schema = OpenBlog::Mcp::Schemas.field(:image_id)
    if OpenBlog::RecordKeys.uuid?(OpenBlog::Image)
      assert_equal({ type: "string", format: "uuid" }, schema)
    else
      assert_equal({ type: "integer", minimum: 1 }, schema)
    end
  end
end
