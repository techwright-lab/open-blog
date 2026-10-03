require_relative "test_helper"
require "minitest/mock"

class BodyRenderingIntegrationTest < ActiveSupport::TestCase
  setup do
    @formats = OpenBlog.config.body_formats
    OpenBlog.config.body_formats = %i[markdown rich_text]
    @image = OpenBlog::Image.create!(sha256: "d" * 64, filename: "garden.png", content_type: "image/png",
      byte_size: 20, width: 40, height: 30)
  end

  teardown do
    OpenBlog.config.body_formats = @formats
  end

  test "publishing records body images in the same order and form that readers receive" do
    result = publish(body: "# Starting seeds\n\n![Seed tray](#{@image.path} \"On the shelf\")\n",
      cover_image: @image, cover_alt: "Garden overview", social_image: @image)
    assert result.success?, result.error&.message
    post = result.post.reload
    html = OpenBlog::Renderer.render(post)
    assert html.html_safe?
    fragment = Nokogiri::HTML5.fragment(html)
    assert_includes fragment.at_css("h2").text, "Starting seeds"
    image = fragment.at_css("figure > img")
    assert_equal @image.path, image["src"]
    assert_equal [ "40", "30", "lazy", "Seed tray" ], %w[width height loading alt].map { |attribute| image[attribute] }
    assert_equal "On the shelf", fragment.at_css("figcaption").text
    entries = JSON.parse(post.public_revision.payload).fetch("images")
    assert_equal %w[cover body social], entries.pluck("role")
    assert_equal image["src"], entries[1]["url"]
    assert_equal @image.sha256, entries[1]["sha256"]
    assert_includes result.findings.pluck(:code), :heading_h1_in_body
    assert_equal post.public_revision.identifier, OpenBlog::RevisionPayload.new(post).identifier
  end

  test "rendering a stored post writes no database records" do
    result = publish(body: "## Contents\n\n![Garden](#{@image.path})\n")
    assert result.success?, result.error&.message
    writes = []
    observer = ->(_name, _start, _finish, _id, data) do
      writes << data[:sql] if data[:sql].match?(/\A\s*(?:INSERT|UPDATE|DELETE|CREATE|ALTER|DROP)\b/i)
    end
    ActiveSupport::Notifications.subscribed(observer, "sql.active_record") do
      2.times { OpenBlog::Renderer.render(result.post.reload) }
      OpenBlog::Renderer.body_images(result.post)
    end
    assert_empty writes
  end

  test "FAQ callback release keeps body image identities after a fresh record load" do
    result = publish(body: "![Garden](#{@image.path})")
    assert result.success?, result.error&.message
    first = JSON.parse(result.post.public_revision.payload).fetch("images")
    assert_equal "body", first.sole.fetch("role")
    result.post.reload.faqs.create!(position: 1, question: "Where?", answer: "By the window.")
    post = result.post.reload
    assert_equal first, JSON.parse(post.public_revision.payload).fetch("images")
    assert_equal post.current_revision_identifier, post.public_revision.identifier
    assert_equal post.public_revision.identifier, OpenBlog::RevisionPayload.new(post).identifier
  end

  test "rich text child writes use raw stored content and retain resolved media in the release" do
    result = publish(body_format: "rich_text", body: "<p>First notes.</p>")
    assert result.success?, result.error&.message
    result.post.rich_body.update!(body: "<p>Updated notes.</p><img src=\"#{@image.path}\" alt=\"Garden\">")
    post = result.post.reload
    payload = JSON.parse(post.public_revision.payload)
    assert_equal post.rich_body.read_attribute_before_type_cast(:body).sub(/\n+\z/, ""), payload.fetch("body")
    assert_equal @image.sha256, payload.fetch("images").sole.fetch("sha256")
    assert_equal @image.path, Nokogiri::HTML5.fragment(OpenBlog::Renderer.render(post)).at_css("img")["src"]
    assert_equal post.public_revision.identifier, OpenBlog::RevisionPayload.new(post).identifier
  end

  test "rich text cannot inject hidden content classes script URLs or fake notices" do
    body = '<div class="ob-notice"><p class="hidden" id="outside" style="display:none" onclick="alert(1)">Visible text.</p></div>' \
      '<a href="javascript:alert(1)">Unsafe link</a><script>alert(1)</script><table><tr><td>Cell</td></tr></table>'
    result = publish(body_format: "rich_text", body: body)
    assert result.success?, result.error&.message
    fragment = Nokogiri::HTML5.fragment(OpenBlog::Renderer.render(result.post))
    assert_nil fragment.at_css(".ob-notice, .hidden, #outside, [style], [onclick], script")
    assert_nil fragment.at_css('a[href^="javascript:"]')
    assert_equal "Visible text.", fragment.at_css("p").text
    assert fragment.at_css("div.ob-table > table")
  end

  test "draft image digests survive reload child saves and metadata-only operations" do
    result = nil
    OpenBlog::ImageResolution.stub(:fetch_external, ->(_url) { "e" * 64 }) do
      result = OpenBlog::SaveDraft.call({ title: "Draft journal", slug: "draft-journal",
        body: "![Tree](https://images.example/tree.png)" }, actor: "Editor")
    end
    assert result.success?, result.error&.message
    post = result.post.reload
    assert_empty post.revisions
    images = OpenBlog::RevisionPayload.new(post).to_h.fetch("images")
    assert_equal "e" * 64, images.sole.fetch("sha256")
    assert_equal "https://images.example/tree.png", images.sole.fetch("url")
    OpenBlog::ImageResolution.stub(:fetch_external, ->(*) { flunk "unchanged bodies must reuse their stored image digests" }) do
      post.faqs.create!(position: 1, question: "Where?", answer: "Outside.")
      updated = OpenBlog::SaveDraft.call({ featured: true }, post: post, actor: "Editor")
      assert updated.success?, updated.error&.message
      assert_equal images, OpenBlog::RevisionPayload.new(updated.post.reload).to_h.fetch("images")
    end
  end

  private

  def publish(**attributes)
    OpenBlog::Publish.call({ title: "Garden journal", slug: "garden-journal" }.merge(attributes), actor: "Editor")
  end
end
