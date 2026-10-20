require_relative "test_helper"

class MediaVariantTest < ActionDispatch::IntegrationTest
  mattr_accessor :representations_closed, default: false

  [ ActiveStorage::Representations::RedirectController, ActiveStorage::Representations::ProxyController ].each do |controller|
    controller.prepend_before_action { head :not_found if MediaVariantTest.representations_closed }
  end

  setup do
    self.representations_closed = true
    @delivery = OpenBlog.config.image_delivery
    bytes = File.binread(OpenBlog::Engine.root.join("lib/generators/open_blog/install/templates/sample_cover.png"))
    @blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(bytes), filename: "cover.png", content_type: "image/png")
    @image = OpenBlog::ImageImport.prepare(signed_id: @blob.signed_id).persist(uploaded_by: "Editor")
    @author = OpenBlog::Author.create!(name: "Robin Green", slug: "robin-green")
    @author.update!(avatar: @image.file.blob)
    @post = OpenBlog::Post.create!(title: "Growing herbs", slug: "growing-herbs", body_markdown: "Fresh soil.",
      status: "published", author: @author, author_name: @author.name, cover_image: @image, cover_alt: "Herbs")
  end

  teardown do
    self.representations_closed = false
    OpenBlog.config.image_delivery = @delivery
    ActiveStorage::Blob.where(id: [ @blob.id ] + ActiveStorage::VariantRecord.where(blob_id: @blob.id).map { |record| record.image.blob.id })
      .each { |blob| blob.service.delete(blob.key) }
  end

  test "cards and avatars use engine variant routes while host representation routes stay closed" do
    get "/blog"
    assert_response :success
    assert_select ".ob-card-image[src=?]", @image.variant_path(:card)
    assert_select "img.ob-avatar[src=?]", @image.variant_path(:avatar)
    refute_includes response.body, "/rails/active_storage/representations/"

    get main_app_representation_path
    assert_response :not_found
  end

  test "proxy delivery serves processed variant bytes with an immutable cache lifetime" do
    OpenBlog.config.image_delivery = :proxy
    { card: [ 640, 360 ], avatar: [ 80, 80 ] }.each do |name, size|
      get @image.variant_path(name)
      assert_response :success
      assert_equal "image/png", response.media_type
      assert_includes response.headers["Cache-Control"], "immutable"
      assert_equal size, MiniMagick::Image.read(response.body).dimensions
    end
  end

  test "redirect delivery sends readers to the stored variant, not a representation route" do
    OpenBlog.config.image_delivery = :redirect
    get @image.variant_path(:card)
    assert_response :redirect
    refute_includes response.location, "/representations/"
    get URI(response.location).request_uri
    assert_response :success
    assert_equal [ 640, 360 ], MiniMagick::Image.read(response.body).dimensions
  end

  test "only named variants of stored blog images are served" do
    get "/blog/media/#{@image.sha256}/huge/cover.png"
    assert_response :not_found
    get "/blog/media/#{'0' * 64}/card/cover.png"
    assert_response :not_found
    assert_raises(ArgumentError) { @image.variant_path(:huge) }
  end

  private

  def main_app_representation_path
    Rails.application.routes.url_helpers.rails_representation_path(@image.file.variant(OpenBlog::Image::VARIANTS.fetch("card")), only_path: true)
  end
end
