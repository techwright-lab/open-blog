require_relative "test_helper"
require "base64"
require "zlib"

class McpApiParityTest < ActionDispatch::IntegrationTest
  setup do
    @settings = %i[authenticate api_rate_limit rate_limit_store].to_h { |key| [ key, OpenBlog.config.public_send(key) ] }
    OpenBlog.config.authenticate = ->(_) { OpenBlog::Actor.new(name: "Parity editor") }
    OpenBlog.config.api_rate_limit = { to: 10000, within: 1.minute }
    OpenBlog.config.rate_limit_store = ActiveSupport::Cache::MemoryStore.new
    travel_to Time.zone.parse("2026-10-04 12:00:00")
    @draft = OpenBlog::SaveDraft.call({ title: "Draft trail", body: "A quiet path." }, actor: "Parity editor").post
    @public = OpenBlog::Publish.call({ title: "Public trail", body: "A woodland path." }, actor: "Parity editor").post
  end

  teardown do
    @settings.each { |key, value| OpenBlog.config.public_send("#{key}=", value) }
    travel_back
    @blob&.service&.delete(@blob.key)
  end

  %w[list_posts search_posts get_post get_post_records check_post save_draft get_preview_link publish_post update_post correct_post approve_revision declare_connections unpublish_post remove_post upload_image list_categories save_category list_tags list_authors save_author list_series save_series list_redirects save_redirect get_site_page save_site_page get_page_views doctor extract_faq adopt_post].each do |name|
    test "#{name} matches its HTTP API result" do
      arguments, method, path, input = example(name)
      expected = rollback_result do
        if name == "upload_image"
          file = Tempfile.new([ "parity-image", ".png" ])
          begin
            file.binmode
            file.write(@image_bytes)
            file.rewind
            upload = Rack::Test::UploadedFile.new(file.path, "image/png", original_filename: "trail.png")
            post "/blog/api/v1/images", params: { file: upload }
          ensure
            file.close!
          end
        else
          public_send(method, "/blog/api/v1#{path}", params: input, as: :json)
        end
        assert response.successful?, response.body
        response.body.empty? ? {} : response.parsed_body
      end
      actual = rollback_result do
        post "/blog/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "blog_#{name}", arguments: arguments } }, as: :json
        assert_response :ok
        result = response.parsed_body.fetch("result")
        refute result["isError"], result.inspect
        result.fetch("structuredContent")
      end
      # Redirect creation allocates an identity in each independent execution.
      if name == "save_redirect"
        assert_kind_of Integer, expected.delete("id")
        assert_kind_of Integer, actual.delete("id")
      end
      assert_equal expected, actual
    end
  end

  private

  def rollback_result
    result = nil
    OpenBlog::Post.transaction(requires_new: true) do
      result = yield
      raise ActiveRecord::Rollback
    end
    result
  end

  def example(name)
    draft = "/posts/#{@draft.id}"
    published = "/posts/#{@public.id}"
    case name
    when "get_page_views" then
      OpenBlog::PageView.create!(post: @public, day: Date.current, views: 4)
      [ { id: @public.slug }, :get, "#{published}/views", {} ]
    when "list_posts" then [ { per_page: 1 }, :get, "/posts", { per_page: 1 } ]
    when "search_posts" then [ { q: "quiet" }, :get, "/posts", { q: "quiet" } ]
    when "get_post" then [ { id: @draft.slug }, :get, draft, {} ]
    when "get_post_records" then [ { id: @public.id }, :get, "#{published}/records", {} ]
    when "check_post" then [ { id: @draft.id }, :get, "#{draft}/findings", {} ]
    when "save_draft" then [ { slug: @draft.slug, description: "A draft description." }, :post, "/posts", { slug: @draft.slug, description: "A draft description.", publish: false } ]
    when "get_preview_link" then [ { id: @draft.id }, :get, "#{draft}/preview", {} ]
    when "publish_post" then [ { id: @draft.id }, :post, "#{draft}/publish", {} ]
    when "update_post" then [ { id: @public.id, body: "An amended path.", change: "substantive" }, :patch, published, { body: "An amended path.", change: "substantive" } ]
    when "correct_post" then [ { id: @public.id, body: "The path is longer.", note: "Corrected the route length." }, :patch, published, { body: "The path is longer.", note: "Corrected the route length.", change: "correction" } ]
    when "approve_revision"
      fields = { revision_identifier: @public.public_revision.identifier, name: "Reviewer", facts_checked: true }
      [ fields.merge(id: @public.id), :post, "#{published}/approvals", fields ]
    when "declare_connections"
      fields = { connections: [], third_party_paid: false, declared_by: "Publisher" }
      [ fields.merge(id: @public.id), :post, "#{published}/connections", fields ]
    when "unpublish_post" then [ { id: @public.id }, :post, "#{published}/unpublish", {} ]
    when "remove_post" then [ { id: @draft.id }, :delete, draft, {} ]
    when "upload_image"
      @image_bytes = "\x89PNG\r\n\x1a\n".b + chunk("IHDR", [ 2, 3, 8, 2, 0, 0, 0 ].pack("NNC5")) +
        chunk("IDAT", Zlib::Deflate.deflate(("\0".b + "\x12\x34\x56".b * 2) * 3)) + chunk("IEND", "".b)
      @blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(@image_bytes), filename: "trail.png", content_type: "image/png", identify: false)
      OpenBlog::Image.from_signed_id(@blob.signed_id, uploaded_by: "Parity editor")
      [ { base64: Base64.strict_encode64(@image_bytes), filename: "trail.png", content_type: "image/png" }, :post, "/images", {} ]
    when "list_categories", "list_tags", "list_authors", "list_series", "list_redirects"
      resource = name.delete_prefix("list_")
      [ {}, :get, "/#{resource}", {} ]
    when "save_category"
      category = OpenBlog::Category.create!(name: "Trails")
      [ { id: category.id, description: "Walking routes" }, :patch, "/categories/#{category.id}", { description: "Walking routes" } ]
    when "save_author"
      author = @draft.author
      [ { id: author.id, bio: "A walker" }, :patch, "/authors/#{author.id}", { bio: "A walker" } ]
    when "save_series"
      series = OpenBlog::Series.create!(name: "Journeys")
      [ { id: series.id, description: "A sequence" }, :patch, "/series/#{series.id}", { description: "A sequence" } ]
    when "save_redirect"
      fields = { old_path: "/blog/previous-trail", new_path: @public.path }
      [ fields, :post, "/redirects", fields ]
    when "get_site_page", "save_site_page"
      OpenBlog::Page.create!(kind: "editorial", title: "Editorial process", body_markdown: "Our editors review each article.")
      if name == "get_site_page"
        [ { kind: "editorial" }, :get, "/pages/editorial", {} ]
      else
        [ { kind: "editorial", body: "Editors review and check facts." }, :put, "/pages/editorial", { body: "Editors review and check facts." } ]
      end
    when "doctor" then [ {}, :get, "/doctor", {} ]
    when "extract_faq"
      fields = { body: "## FAQ\n\n### When?\n\nAt dawn.\n" }
      [ fields, :post, "/faq_extractions", fields ]
    when "adopt_post"
      fields = { source_system: "archive", source_id: "trail-1", title: "Old trail", slug: "old-trail", body_format: "markdown", body: "The old path." }
      result = OpenBlog::Adopt.call(fields, actor: "Parity editor")
      assert result.success?, result.error&.message
      [ fields, :post, "/adoptions", fields ]
    end
  end

  def chunk(type, data)
    [ data.bytesize ].pack("N") + type + data + [ Zlib.crc32(type + data) ].pack("N")
  end
end
