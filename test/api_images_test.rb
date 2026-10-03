require_relative "test_helper"
require "minitest/mock"
require "zlib"
require "tempfile"

class ApiImagesTest < ActionDispatch::IntegrationTest
  setup do
    @hook = OpenBlog.config.authenticate
    @limit = OpenBlog.config.max_image_bytes
    OpenBlog.config.authenticate = ->(_) { OpenBlog::Actor.new(name: "Image editor") }
    @file = Tempfile.new([ "image", ".png" ], binmode: true)
    @file.write(png)
    @file.rewind
  end

  teardown do
    OpenBlog.config.authenticate = @hook
    OpenBlog.config.max_image_bytes = @limit
    @file.close!
  end

  test "multipart upload returns exact image fields and reuses identical bytes" do
    upload = Rack::Test::UploadedFile.new(@file.path, "image/png")
    post "/blog/api/v1/images", params: { file: upload }
    assert_response :created
    first = response.parsed_body
    assert_equal %w[byte_size content_type filename height image_id sha256 url width], first.keys.sort
    assert_equal Digest::SHA256.hexdigest(png), first.fetch("sha256")
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_nil response.headers["Set-Cookie"]
    assert_no_difference [ "OpenBlog::Image.count", "ActiveStorage::Blob.count" ] do
      post "/blog/api/v1/images", params: { file: upload }
      assert_response :created
      assert_equal first, response.parsed_body
    end
  end

  test "URL input fetches before the image transaction and closes its stream" do
    depth = ActiveRecord::Base.connection.open_transactions
    stream = StringIO.new(png)
    fetch = lambda do |url, **|
      assert_equal "https://images.example/field.png", url
      assert_equal depth, ActiveRecord::Base.connection.open_transactions
      { io: stream, content_type: "image/png", filename: "field.png" }
    end
    OpenBlog::ImageFetch.stub(:call, fetch) do
      post "/blog/api/v1/images", params: { url: "https://images.example/field.png" }, as: :json
      assert_response :created
    end
    assert stream.closed?
  end

  test "unsupported bytes excess size ambiguous and unknown inputs store nothing" do
    assert_no_difference [ "OpenBlog::Image.count", "ActiveStorage::Blob.count" ] do
      post "/blog/api/v1/images", params: { file: "not a file" }, as: :json
      assert_error "image_not_permitted"
      post "/blog/api/v1/images", params: { url: "https://images.example/field.png", file: "other" }, as: :json
      assert_error "image_not_permitted"
      post "/blog/api/v1/images", params: { unsupported: true }, as: :json
      assert_error "unknown_field"
      OpenBlog.config.max_image_bytes = png.bytesize - 1
      post "/blog/api/v1/images", params: { file: Rack::Test::UploadedFile.new(@file.path, "image/png") }
      assert_error "image_not_permitted"
      OpenBlog.config.max_image_bytes = @limit
      @file.rewind
      @file.truncate(0)
      @file.write('<svg xmlns="http://www.w3.org/2000/svg"></svg>')
      @file.flush
      post "/blog/api/v1/images", params: { file: Rack::Test::UploadedFile.new(@file.path, "image/svg+xml") }
      assert_error "image_not_permitted"
    end
  end

  test "image scope is enforced before fetching" do
    OpenBlog.config.authenticate = ->(_) { OpenBlog::Actor.new(name: "Reader", scopes: [ "read" ]) }
    OpenBlog::ImageFetch.stub(:call, ->(*) { flunk "Unauthorized fetch" }) do
      post "/blog/api/v1/images", params: { url: "https://images.example/field.png" }, as: :json
      assert_response :forbidden
      assert_equal "scope_required", response.parsed_body.dig("error", "code")
      assert_equal "no-store", response.headers["Cache-Control"]
    end
  end

  private

  def assert_error(code)
    assert_response :unprocessable_entity
    assert_equal code, response.parsed_body.dig("error", "code")
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  def png
    "\x89PNG\r\n\x1a\n".b + chunk("IHDR", [ 2, 2, 8, 2, 0, 0, 0 ].pack("NNC5")) +
      chunk("IDAT", Zlib::Deflate.deflate(("\0".b + "\x12\x34\x56".b * 2) * 2)) + chunk("IEND", "".b)
  end

  def chunk(type, data)
    [ data.bytesize ].pack("N") + type + data + [ Zlib.crc32(type + data) ].pack("N")
  end
end
