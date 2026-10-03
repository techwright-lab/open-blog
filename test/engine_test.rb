require_relative "test_helper"

class EngineTest < ActionDispatch::IntegrationTest
  test "a configured mounted engine serves the reader index" do
    get "/blog"
    assert_response :success
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
    assert_includes Rails.application.config.assets.paths.map(&:to_s), OpenBlog::Engine.root.join("app/assets/builds").to_s
    assert_includes Rails.application.config.assets.paths.map(&:to_s), OpenBlog::Engine.root.join("app/assets/javascripts").to_s
  end

  test "reader stylesheet and imported controller modules are served at their logical URLs" do
    get "/blog"
    assert_response :success
    document = Nokogiri::HTML5(response.body)
    stylesheet = document.at_css('link[rel="stylesheet"]')["href"]
    imports = JSON.parse(document.at_css('script[type="importmap"]').text).fetch("imports")
    controllers = imports.select { |name, _path| name.start_with?("controllers/open_blog/") }
    assert_equal 5, controllers.size
    [ stylesheet, imports.fetch("application"), imports.fetch("@hotwired/stimulus"), *controllers.values ].each do |path|
      get path
      assert_response :success, path
      assert_includes [ "text/css", "text/javascript", "application/javascript" ], response.media_type
    end
  end

  test "engine leaves importmap pins to the host" do
    refute Rails.application.config.importmap.paths.any? { |path| path.to_s.start_with?(OpenBlog::Engine.root.join("config").to_s) }
  end
end
