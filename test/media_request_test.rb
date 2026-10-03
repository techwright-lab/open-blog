require_relative "test_helper"

class MediaRequestTest < ActionDispatch::IntegrationTest
  setup do
    @delivery = OpenBlog.config.image_delivery
    @blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("Original bytes"), filename: "leaf.png", content_type: "image/png", identify: false)
    @image = OpenBlog::Image.new(sha256: "a" * 64, filename: "leaf.png", content_type: "image/png", byte_size: @blob.byte_size)
    @image.file = @blob
    @image.save!
  end

  teardown do
    OpenBlog.config.image_delivery = @delivery
    @blob.service.delete(@blob.key)
  end

  test "proxy media serves immutable original bytes independently of the filename" do
    OpenBlog.config.image_delivery = :proxy
    get "/blog/media/#{@image.sha256}/different.png"
    assert_response :success
    assert_equal "Original bytes", response.body
    assert_equal "image/png", response.media_type
    assert_includes response.headers["Cache-Control"], "max-age=31536000"
    get "/blog/media/#{'b' * 64}/missing.png"
    assert_response :not_found
  end

  test "redirect media cache lifetime does not exceed its signed target lifetime" do
    OpenBlog.config.image_delivery = :redirect
    get @image.path
    assert_response :found
    assert_match %r{/rails/active_storage/disk/}, response.location
    lifetime = response.headers.fetch("Cache-Control")[/max-age=(\d+)/, 1].to_i
    assert_operator lifetime, :>, 0
    assert_operator lifetime, :<=, ActiveStorage.service_urls_expire_in.to_i
  end
end
