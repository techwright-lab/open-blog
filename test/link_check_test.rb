require_relative "test_helper"

class LinkCheckTest < ActiveSupport::TestCase
  setup do
    @author = OpenBlog::Author.create!(name: "Link author", slug: "link-author")
    @post = OpenBlog::Post.create!(title: "Links", slug: "links", author: @author, author_name: @author.name, body_markdown: "Text.")
  end

  test "each distinct missing local link is located without reporting external or self links" do
    @post.body_markdown = %w[/blog/absent absent /pricing /blogger/absent https://elsewhere.example/blog/absent https://example.test:444/blog/absent http://example.test/blog/absent /blog/api/v1/posts /blog/mcp #section ?page=2].map { |href| "[Link](#{href})" }.join("\n\n") + "\n\n[Again](/blog/absent)"
    assert_equal [ "/blog/absent", "absent" ], locations
  end

  test "public posts redirects feeds and existing taxonomy routes resolve but drafts do not" do
    public_post = OpenBlog::Post.create!(title: "Public", slug: "public", author: @author, author_name: @author.name, status: "published")
    category = OpenBlog::Category.create!(name: "Links")
    OpenBlog::Redirect.create!(old_path: "/blog/old", new_path: public_post.path, source: "manual", occurred_on: Date.current)
    OpenBlog::Redirect.create!(old_path: "/blog/gone", source: "manual", occurred_on: Date.current)
    valid = [ public_post.path, "#{public_post.path}.md", "/blog/old", "/blog/gone", "/blog/feed.xml", "/blog/feed.json", "/blog/category/#{category.slug}", "/blog/category/#{category.slug}/feed.json", "/blog/search?q=trees", "/blog/author/link-author" ]
    @post.body_markdown = (valid + [ @post.path, "/blog/category/missing", "#{public_post.path}.json" ]).map { |href| "[Link](#{href})" }.join("\n\n")
    assert_equal [ @post.path, "/blog/category/missing", "#{public_post.path}.json" ], locations
  end

  test "policy overrides and preview expiry follow actual reader visibility" do
    policy = OpenBlog::Page.create!(kind: "editorial", title: "Editorial", body_markdown: "Process.", status: "published")
    preview = OpenBlog::PreviewSerializer.call(@post).fetch(:preview_url)
    @post.body_markdown = "[Policy](#{policy.path})"
    assert_empty locations
    saved = OpenBlog.config.policy_urls.dup
    OpenBlog.config.policy_urls[:editorial] = "https://publisher.example/editorial"
    assert_equal [ policy.path ], locations
    # The token is bound to the stored revision, not this unsaved checker input.
    @post.reload
    checker = OpenBlog::Post.new(title: "Checker", slug: "checker", body_markdown: "[Preview](#{preview})")
    assert_empty OpenBlog::Findings.for(checker).select { |finding| finding[:code] == :link_same_site_broken }
    travel 8.days do
      assert_equal [ preview ], OpenBlog::Findings.for(checker).select { |finding| finding[:code] == :link_same_site_broken }.map { |finding| finding[:location] }
    end
  ensure
    OpenBlog.config.policy_urls = saved if saved
  end


  test "origin normalization protected routes and disabled sitemap remain local and read only" do
    original = OpenBlog.config.serve_sitemap
    OpenBlog.config.serve_sitemap = false
    @post.body_markdown = [ "https://example.test/blog/missing", "//example.test/blog/missing", "../blog/missing",
      "/blog/sitemap.xml", "/blog/api/v1/posts/123", "/blog/mcp/anything", "mailto:editor@example.test" ].map { |href| "[Link](#{href})" }.join("\n\n")
    writes = []
    observer = ->(*arguments) { sql = arguments.last[:sql]; writes << sql if sql.match?(/\A\s*(INSERT|UPDATE|DELETE)\b/i) }
    actual = nil
    ActiveSupport::Notifications.subscribed(observer, "sql.active_record") { actual = locations }
    assert_equal [ "https://example.test/blog/missing", "//example.test/blog/missing", "../blog/missing", "/blog/sitemap.xml" ], actual
    assert_empty writes
  ensure
    OpenBlog.config.serve_sitemap = original
  end

  test "preview links reject archived changed and unsupported representations" do
    preview = OpenBlog::PreviewSerializer.call(@post).fetch(:preview_url)
    checker = OpenBlog::Post.new(slug: "checker", body_markdown: "[Preview](#{preview})")
    @post.update!(status: "published")
    assert_empty OpenBlog::Findings::LinkCheck.new.call(checker)
    @post.update!(status: "archived")
    assert_equal [ preview ], OpenBlog::Findings::LinkCheck.new.call(checker).map { |finding| finding[:location] }
    @post.update!(status: "draft", body_markdown: "Changed content.")
    assert_equal [ preview ], OpenBlog::Findings::LinkCheck.new.call(checker).map { |finding| finding[:location] }
    fresh = OpenBlog::PreviewSerializer.call(@post).fetch(:preview_url)
    checker.body_markdown = "[Preview](#{fresh}.json)"
    assert_equal [ "#{fresh}.json" ], OpenBlog::Findings::LinkCheck.new.call(checker).map { |finding| finding[:location] }
  end

  private

  def locations
    OpenBlog::Findings.for(@post).select { |finding| finding[:code] == :link_same_site_broken }.map { |finding| finding[:location] }
  end
end


class LinkCheckRedirectTest < ActionDispatch::IntegrationTest
  test "redirect aliases follow reader routes rather than arbitrary stored paths" do
    OpenBlog::Redirect.create!(old_path: "/blog/old-link", new_path: "/blog/destination", source: "manual", occurred_on: Date.current)
    OpenBlog::Redirect.create!(old_path: "/blog/nested/old", new_path: "/blog/destination", source: "manual", occurred_on: Date.current)
    OpenBlog::Redirect.create!(old_path: "/blog/unsupported.json", new_path: "/blog/destination", source: "manual", occurred_on: Date.current)
    checker = OpenBlog::Post.new(slug: "checker")
    [ "/blog/old-link.md", "/blog/old-link.html" ].each do |path|
      get path
      assert_response :moved_permanently
      assert_redirected_to "/blog/destination"
      checker.body_markdown = "[Old post](#{path})"
      assert_empty OpenBlog::Findings::LinkCheck.new.call(checker), path
    end
    [ "/blog/nested/old", "/blog/unsupported.json", "/blog/old-link.json" ].each do |path|
      get path
      assert_response :not_found
      checker.body_markdown = "[Missing page](#{path})"
      assert_equal [ path ], OpenBlog::Findings::LinkCheck.new.call(checker).map { |finding| finding[:location] }
    end
  end
end
