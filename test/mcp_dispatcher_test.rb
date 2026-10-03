require_relative "test_helper"
require "minitest/mock"

class McpDispatcherTest < ActiveSupport::TestCase
  test "trusted actor dispatch uses existing API behavior without authentication hooks or extra quota" do
    refute OpenBlog::Api::V1::PostsController.action_methods.include?("dispatch_internal")
    actor = OpenBlog::Actor.new(name: "Registry editor")
    hook = OpenBlog.config.authenticate
    store = OpenBlog.config.rate_limit_store
    OpenBlog.config.authenticate = ->(_) { flunk "Internal dispatch must not reauthenticate" }
    OpenBlog.config.rate_limit_store = Object.new
    result = OpenBlog::Mcp::Dispatcher.call(controller: "posts", action: "create", method: :post,
      arguments: { title: "Bird notes", body: "A robin crossed the path." }, actor: actor)
    assert_equal "draft", result.dig("post", "status")
    assert_equal "Bird notes", result.dig("post", "title")
    assert_equal true, result["created"]
    assert_equal 1, OpenBlog::Post.count
  ensure
    OpenBlog.config.authenticate = hook
    OpenBlog.config.rate_limit_store = store
  end

  test "internal dispatch retains API scope and unknown field refusals" do
    actor = OpenBlog::Actor.new(name: "Observer", scopes: [])
    result = OpenBlog::Mcp::Dispatcher.call(controller: "posts", action: "index", method: :get, arguments: {}, actor: actor)
    assert_equal "scope_required", result.dig("error", "code")
    result = OpenBlog::Mcp::Dispatcher.call(controller: "posts", action: "index", method: :get,
      arguments: { actor: "forged" }, actor: OpenBlog::Actor.new(name: "Reader"))
    assert_equal "unknown_field", result.dig("error", "code")
    assert_equal [ "actor" ], result.dig("error", "details")
  end

  test "definition enforces declared scope and schema for direct host callers" do
    handler = ->(arguments, actor:, base_url:) { { "value" => arguments[:value], "actor" => actor.name, "base_url" => base_url } }
    definition = OpenBlog::Mcp::Definition.new(name: "blog_test", title: "Test", description: "Test tool",
      scope: :publish, annotations: {}, input_schema: { type: "object", properties: { value: { type: "integer" } }, required: [ "value" ], additionalProperties: false }, handler: handler)
    result = definition.call({ value: 2 }, actor: OpenBlog::Actor.new(name: "Reader", scopes: [ "read" ]))
    assert_equal "scope_required", result.dig("error", "code")
    result = definition.call({ value: "bad" }, actor: OpenBlog::Actor.new(name: "Editor"))
    assert_equal "validation_failed", result.dig("error", "code")
    result = definition.call({ value: 2 }, actor: OpenBlog::Actor.new(name: "Editor"), base_url: "https://notes.example")
    assert_equal({ "value" => 2, "actor" => "Editor", "base_url" => "https://notes.example" }, result)
  end
end
