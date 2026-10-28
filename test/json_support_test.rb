require "minitest/autorun"
require "open_blog"

class JsonSupportTest < Minitest::Test
  def test_accepts_json_2_on_rails_8_0_and_8_1
    %w[8.0.5.1 8.1.4].each do |rails|
      assert_nil OpenBlog.require_supported_json!(rails: Gem::Version.new(rails), json: Gem::Version.new("2.21.2"))
    end
  end

  def test_accepts_json_3_on_rails_8_1_and_later
    %w[8.1.0 8.1.4 8.2.0.beta1].each do |rails|
      assert_nil OpenBlog.require_supported_json!(rails: Gem::Version.new(rails), json: Gem::Version.new("3.1.0"))
    end
  end

  def test_refuses_json_3_on_rails_8_0
    error = assert_raises(OpenBlog::ConfigurationError) do
      OpenBlog.require_supported_json!(rails: Gem::Version.new("8.0.5.1"), json: Gem::Version.new("3.0.2"))
    end
    assert_includes error.message, "quirks_mode"
    assert_includes error.message, 'gem "json", "< 3"'
  end

  def test_loaded_versions_are_supported
    assert_nil OpenBlog.require_supported_json!
  end
end
