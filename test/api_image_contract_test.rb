require_relative "test_helper"

class ApiImageContractTest < ActionDispatch::IntegrationTest
  setup do
    @hook = OpenBlog.config.authenticate
    OpenBlog.config.authenticate = ->(_) { OpenBlog::Actor.new(name: "Editor") }
    @image = OpenBlog::Image.create!(sha256: "a" * 64, filename: "image.png", content_type: "image/png", byte_size: 10, width: 2, height: 3)
  end
  teardown { OpenBlog.config.authenticate = @hook }

  test "HTTP post image inputs use the same object contract as tool inputs" do
    [ @image.id, { image_id: @image.id.to_s } ].each do |value|
      post "/blog/api/v1/posts", params: { title: "Image note", cover_image: value }, as: :json
      assert_response :unprocessable_entity
      assert_equal "image_not_permitted", response.parsed_body.dig("error", "code")
    end
    assert_equal 0, OpenBlog::Post.count
    post "/blog/api/v1/posts", params: { title: "Image note", cover_image: { image_id: @image.id } }, as: :json
    assert_response :created
    assert_equal @image.id, response.parsed_body.dig("post", "cover_image", "image_id")
  end
end
