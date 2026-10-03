require_relative "test_helper"
require "minitest/mock"

class McpRegistryTest < ActiveSupport::TestCase
  NAMES = %w[list_posts search_posts get_post get_post_records check_post save_draft get_preview_link publish_post update_post correct_post approve_revision declare_connections unpublish_post remove_post upload_image list_categories save_category list_tags list_authors save_author list_series save_series list_redirects save_redirect get_site_page save_site_page get_page_views doctor extract_faq adopt_post].map { |name| "blog_#{name}" }.freeze

  test "registry exposes exactly the implemented tools with strict object schemas" do
    definitions = OpenBlog::Mcp.definitions
    assert_equal NAMES.sort, definitions.map(&:name).sort
    definitions.each do |definition|
      schema = definition.input_schema.deep_stringify_keys
      assert_equal "object", schema["type"]
      assert_equal false, schema["additionalProperties"]
      assert_equal(definition.scope.to_s == "read", definition.annotations[:read_only_hint] || definition.annotations["readOnlyHint"] || false)
    end
    remove = definitions.find { |definition| definition.name == "blog_remove_post" }
    assert remove.annotations[:destructive_hint] || remove.annotations["destructiveHint"]
  end

  test "shared endpoint field lists match registry properties without route or transport fields" do
    { "save_draft" => OpenBlog::ApiFields::POST_WRITE, "list_posts" => OpenBlog::ApiFields::POST_LIST,
      "approve_revision" => OpenBlog::ApiFields::APPROVAL, "declare_connections" => OpenBlog::ApiFields::CONNECTION,
      "save_category" => OpenBlog::ApiFields::CATEGORY, "save_author" => OpenBlog::ApiFields::AUTHOR,
      "save_series" => OpenBlog::ApiFields::SERIES, "save_redirect" => OpenBlog::ApiFields::REDIRECT,
      "extract_faq" => OpenBlog::ApiFields::EXTRACTION, "adopt_post" => OpenBlog::ApiFields::ADOPTION }.each do |name, fields|
      definition = OpenBlog::Mcp.definitions.find { |entry| entry.name == "blog_#{name}" }
      properties = definition.input_schema.deep_stringify_keys.fetch("properties").keys - [ "id" ]
      assert_equal fields.map(&:to_s).sort, properties.sort, name
    end
  end
  test "list tools honor the configured MCP page limit without changing total" do
    previous = OpenBlog.config.mcp.max_page_size
    OpenBlog.config.mcp.max_page_size = 2
    3.times { |index| OpenBlog::SaveDraft.call({ title: "Page #{index}" }, actor: "Editor") }
    definition = OpenBlog::Mcp.definitions.find { |entry| entry.name == "blog_list_posts" }
    result = definition.call({ per_page: 100 }, actor: OpenBlog::Actor.new(name: "Reader", scopes: [ "read" ]))
    assert_equal 2, result["per_page"]
    assert_equal 2, result["posts"].size
    assert_equal 3, result["total"]
  ensure
    OpenBlog.config.mcp.max_page_size = previous
  end

  test "base64 rejects excessive encoded input before decoding or writing" do
    previous = OpenBlog.config.max_image_bytes
    OpenBlog.config.max_image_bytes = 3
    Base64.stub(:strict_decode64, ->(_) { flunk "Oversized input must be rejected before allocating decoded bytes" }) do
      assert_raises(OpenBlog::Error::ImageNotPermitted) do
        OpenBlog::Mcp::ImageInput.with_upload(base64: "AAAA" * 2, filename: "image.png", content_type: "image/png") { flunk "Unexpected upload" }
      end
    end
  ensure
    OpenBlog.config.max_image_bytes = previous
  end

  test "direct definitions reject unknown nested fields conflicting corrections and missing required identity" do
    actor = OpenBlog::Actor.new(name: "Editor")
    [ [ "save_draft", { title: "Note", faq: [ { question: "When?", answer: "Now", hidden: true } ] } ],
      [ "correct_post", { id: "note", note: "Correction", change: "maintenance" } ],
      [ "update_post", { body: "Edited" } ] ].each do |name, arguments|
      result = OpenBlog::Mcp.definitions.find { |entry| entry.name == "blog_#{name}" }.call(arguments, actor: actor)
      assert_equal "validation_failed", result.dig("error", "code")
    end
    limited = OpenBlog::Actor.new(name: "Reader", scopes: [ "read" ])
    result = OpenBlog::Mcp.definitions.find { |entry| entry.name == "blog_publish_post" }.call({ title: "Note" }, actor: limited)
    assert_equal "scope_required", result.dig("error", "code")
  end

  test "publish without an id uses upsert while category saves without an id create" do
    actor = OpenBlog::Actor.new(name: "Editor")
    result = OpenBlog::Mcp.definitions.find { |entry| entry.name == "blog_publish_post" }.call({ title: "New trail", body: "A path." }, actor: actor)
    assert_equal true, result["created"]
    assert_equal "published", result.dig("post", "status")
    category = OpenBlog::Mcp.definitions.find { |entry| entry.name == "blog_save_category" }.call({ name: "Hiking" }, actor: actor)
    assert_equal "hiking", category["slug"]
  end
end
