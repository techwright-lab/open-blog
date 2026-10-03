require_relative "test_helper"
require "minitest/mock"

class RendererLocaleTest < ActiveSupport::TestCase
  test "code controls remain inert without JavaScript and cached labels follow configured locale" do
    original_locale = OpenBlog.config.locale
    original_available = I18n.available_locales
    I18n.available_locales = original_available | [ :fr ]
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    I18n.backend.store_translations(:fr, open_blog: { headings: { link: "Lien vers %{heading}" }, code: { copy: "Copier", copy_label: "Copier le code", copied: "Copié", copy_failed: "Échec de copie" } })
    author = OpenBlog::Author.create!(name: "River Editor", slug: "river-editor", author_type: "person")
    post = OpenBlog::Post.create!(author: author, author_name: author.name, title: "A code sample", slug: "code-sample", body_markdown: "## Garden\n\n```ruby\nputs :hello\n```", body_format: "markdown")
    OpenBlog.config.locale = :en
    english = Nokogiri::HTML5.fragment(OpenBlog::Renderer.render(post))
    button = english.at_css(".ob-code-copy")
    assert button.key?("hidden")
    assert_equal "Copy", button.text
    assert_equal "Copy code", button["aria-label"]
    assert_equal "polite", button["aria-live"]
    OpenBlog.config.locale = :fr
    french = Nokogiri::HTML5.fragment(OpenBlog::Renderer.render(post))
    assert_equal "Copier", french.at_css(".ob-code-copy").text
    assert_equal "Copier le code", french.at_css(".ob-code-copy")["aria-label"]
    assert_equal "Copié", french.at_css("pre")["data-open-blog--code-copy-copied-label-value"]
    assert_equal "Échec de copie", french.at_css("pre")["data-open-blog--code-copy-error-label-value"]
    assert_equal "puts :hello\n", french.at_css("code").text
    assert_equal "Lien vers Garden", french.at_css(".ob-heading-anchor")["aria-label"]
  ensure
    OpenBlog.config.locale = original_locale
    I18n.available_locales = original_available
    Rails.cache = original_cache
  end
end
