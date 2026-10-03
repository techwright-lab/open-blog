require_relative "test_helper"

class EngineTest < ActionDispatch::IntegrationTest
  test "a configured mounted engine returns not found without content routes" do
    get "/blog"
    assert_response :not_found
  end

  test "engine is isolated and resolves its mounted path" do
    assert OpenBlog::Engine.isolated?
    assert_equal "open_blog", OpenBlog::Engine.engine_name
    assert_equal "/blog", OpenBlog.mount_path
  end

  test "configuration block returns the shared configuration" do
    assert_same OpenBlog.config, OpenBlog.configure { |_configuration| }
    assert_same Rails.cache, OpenBlog.config.rate_limit_store
  end

  test "engine registers markdown and supplies its asset path" do
    assert_equal "text/markdown", Mime[:md].to_s
    assert_includes Rails.application.config.assets.paths.map(&:to_s), OpenBlog::Engine.root.join("app/assets").to_s
  end

  test "engine leaves importmap pins to the host" do
    refute Rails.application.config.importmap.paths.any? { |path| path.to_s.start_with?(OpenBlog::Engine.root.join("config").to_s) }
  end
end
