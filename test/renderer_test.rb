require_relative "test_helper"
require "minitest/mock"

class RendererTest < ActiveSupport::TestCase
  setup do
    @hardbreaks = OpenBlog.config.markdown_hardbreaks
    @base = OpenBlog.config.public_base_url
    OpenBlog.config.public_base_url = "https://journal.example"
  end

  teardown do
    OpenBlog.config.markdown_hardbreaks = @hardbreaks
    OpenBlog.config.public_base_url = @base
  end

  test "Markdown features retain safe structural markup" do
    body = <<~MARKDOWN
      | Item | Count |
      | --- | --- |
      | Seeds | 12 |

      - [x] Prepare beds
      - [ ] Plant seeds

      > [!NOTE]
      > Keep the soil moist.

      ~~Old advice~~ and https://journal.example/notes

      A detail[^seed].

      [^seed]: Store in a dry place.
    MARKDOWN
    doc = render_body(body)
    assert doc.at_css("div.ob-table > table")
    assert_equal 2, doc.css('input[type="checkbox"][disabled]').length
    assert_equal 1, doc.css("input[checked]").length
    assert doc.at_css("div.markdown-alert-note")
    assert_equal "Old advice", doc.at_css("del").text
    assert doc.at_css('a[href="https://journal.example/notes"]')
    assert doc.at_css("a[data-footnote-ref]")
    assert doc.at_css("section[data-footnotes]")
    doc.css('a[href^="#"]').each do |link|
      assert doc.at_css("[id='#{link['href'].delete_prefix('#')}']"), "missing target for #{link['href']}"
    end
    refute_includes doc.to_html, "data-ob-render-token"
  end

  test "compiler footnotes cannot collide with generated heading anchors" do
    doc = render_body("# Footnote\n\n# Footnote\n\nText[^note].\n\n[^note]: A note.\n")
    ids = doc.css("[id]").map { |node| node["id"] }
    assert_equal ids.uniq, ids
    assert_equal [ "footnote", "footnote-1" ], doc.css("h2").map { |node| node["id"] }
  end

  test "headings shift to h2 and every heading has a unique self link" do
    doc = render_body("# Setup\n\n## Detail\n\n# Setup\n")
    assert_empty doc.css("h1")
    assert_equal [ "Setup", "Setup" ], doc.css("h2").map { |node| node.text.delete_suffix("#").strip }
    assert_equal [ "setup", "detail", "setup-1" ], doc.css("h2, h3").map { |node| node["id"] }
    doc.css("h2, h3").each { |node| assert node.at_css("a[href='##{node['id']}']") }
    assert_equal "Start", render_body("### Start\n").at_css("h2").text.delete_suffix("#").strip
  end

  test "scrollable tables and code remain keyboard accessible without JavaScript" do
    doc = render_body("| Plant | Care |\n| --- | --- |\n| Tree | Water |\n\n```ruby\nputs :garden\n```\n")
    assert_equal "0", doc.at_css(".ob-table")["tabindex"]
    assert_equal "0", doc.at_css("pre")["tabindex"]
    assert doc.at_css("pre button").key?("hidden")
    assert_equal "puts :garden\n", doc.at_css("pre code").text
  end

  test "Ruby code uses Rouge and an unknown language stays plain" do
    doc = render_body("```ruby\ndef water\n  true\nend\n```\n\n```invented_language\n<tag> & value\n```\n")
    ruby = doc.at_css('pre.ob-highlight[data-lang="ruby"]')
    assert ruby
    assert ruby.at_css("span.k")
    assert_equal "ruby", ruby.at_css(".ob-code-language")&.text
    assert doc.at_css('button[data-action="open-blog--code-copy#copy"]')
    unknown = doc.at_css('pre[data-lang="invented_language"]')
    assert_equal "<tag> & value\n", unknown.at_css("code").text
    assert_empty unknown.css("code span")
    refute unknown.at_css("tag")
  end

  test "Markdown line breaks follow configuration and raw HTML is removed" do
    OpenBlog.config.markdown_hardbreaks = true
    assert render_body("a\nb").at_css("br")
    OpenBlog.config.markdown_hardbreaks = false
    refute render_body("a\nb").at_css("br")
    doc = render_body("<script>alert(1)</script>\n\n<p class='hidden'>Hidden</p>\n")
    assert_empty doc.css("script, .hidden")
  end

  test "rich HTML cannot supply presentation attributes or compiler trust" do
    doc = render_body(<<~HTML, format: :rich_text)
      <p class="hidden" id="spoof" style="display:none" onclick="bad()">Visible</p>
      <div class="ob-notice markdown-alert-note" data-ob-render-token="0">No notice</div>
      <a href="#missing" data-footnote-ref="">No footnote</a>
      <section data-footnotes="">No footnotes</section>
    HTML
    assert_empty doc.at_css("p").attributes
    assert_empty doc.css(".ob-notice, .markdown-alert-note, [data-footnote-ref], [data-footnotes], [data-ob-render-token]")
    assert_empty doc.css("#spoof, [style], [onclick]")
    assert_includes doc.text, "Visible"
  end

  test "only disabled checkboxes survive and dangerous URLs are removed" do
    doc = render_body(<<~HTML, format: :rich_text)
      <input type="checkbox" disabled checked><input type="checkbox"><input type="text" disabled>
      <a href="javascript:alert(1)">Bad</a><a href="ftp://outside.example/file">FTP</a>
      <a href="mailto:writer@example.test">Email</a><a href="/local">Local</a>
      <img src="data:image/svg+xml,bad" alt="Bad image">
    HTML
    assert_equal 1, doc.css("input").length
    assert doc.at_css('input[type="checkbox"][disabled][checked]')
    assert_equal 2, doc.css("a[href]").length
    assert doc.at_css('a[href="mailto:writer@example.test"]')
    assert_empty doc.css("img")
  end

  test "external links receive noopener and local links do not" do
    doc = render_body("[Away](https://other.example/page) [Here](/local) [Same](https://journal.example/page)")
    assert_includes doc.at_css('a[href="https://other.example/page"]')["rel"].split, "noopener"
    assert_nil doc.at_css('a[href="/local"]')["rel"]
    assert_nil doc.at_css('a[href="https://journal.example/page"]')["rel"]
  end

  test "image titles become escaped captions and images load lazily" do
    doc = render_body('![A seedling](https://images.example/seedling.png "First season")')
    assert_equal "A seedling", doc.at_css("figure > img")["alt"]
    assert_equal "lazy", doc.at_css("figure > img")["loading"]
    assert_equal "First season", doc.at_css("figure > figcaption").text
    refute_match(/<p>\s*<figure/, OpenBlog::Renderer.render_string("![Seedling](/leaf.png)", format: :markdown))
    malicious = render_body('<img src="/leaf.png" title="&lt;script&gt;bad&lt;/script&gt;">', format: :rich_text)
    assert_equal "<script>bad</script>", malicious.at_css("figcaption").text
    assert_empty malicious.css("script")
  end

  test "empty and ASCII encoded Markdown render without errors" do
    assert_equal "", OpenBlog::Renderer.render_string(nil, format: :markdown)
    assert_equal "<p>Text</p>\n", OpenBlog::Renderer.render_string("Text".encode(Encoding::US_ASCII), format: :markdown)
  end

  test "images in one paragraph retain surrounding text in order" do
    doc = render_body("Before ![One](/one.png) middle ![Two](/two.png) after")
    assert_equal %w[p figure p figure p], doc.children.select(&:element?).map(&:name)
    assert_equal [ "Before ", " middle ", " after" ], doc.css("p").map(&:text)
    assert_equal [ "/one.png", "/two.png" ], doc.css("figure img").map { |node| node["src"] }
  end

  test "linked Markdown images remain clickable inside valid figures" do
    html = OpenBlog::Renderer.render_string("Before [![Leaf](/leaf.png)](/garden) after", format: :markdown)
    doc = Nokogiri::HTML5.fragment(html)
    assert_equal %w[p figure p], doc.children.select(&:element?).map(&:name)
    assert_equal "/garden", doc.at_css("figure > a")["href"]
    assert_equal "/leaf.png", doc.at_css("figure > a > img")["src"]
    assert_equal [ "Before ", " after" ], doc.css("p").map(&:text)
  end

  test "figures split mixed inline wrappers while preserving text formatting and links" do
    body = '<p>Before <em>words<a href="/garden">label<img src="/leaf.png">after</a>end</em> tail</p>'
    html = OpenBlog::Renderer.render_string(body, format: :rich_text)
    doc = Nokogiri::HTML5.fragment(html)
    assert_equal %w[p figure p], doc.children.select(&:element?).map(&:name)
    assert_equal [ "Before wordslabel", "afterend tail" ], doc.css("p").map(&:text)
    assert_equal "/garden", doc.at_css("figure > em > a")["href"]
    assert_equal "/leaf.png", doc.at_css("figure > em > a > img")["src"]
    assert_equal "label", doc.at_css("p:first-child em a").text
    assert_equal "after", doc.at_css("p:last-child em a").text
    uncorrected = Nokogiri::XML.fragment(html)
    assert_empty uncorrected.css("p figure, em figure, a figure")
  end

  test "emphasized linked Markdown images keep both formatting and paragraph text" do
    doc = render_body("Before *words [![Leaf](/leaf.png)](/garden) after* tail")
    assert_equal [ "Before words ", " after tail" ], doc.css("p").map(&:text)
    assert_equal "/garden", doc.at_css("figure > em > a")["href"]
    assert_equal "/leaf.png", doc.at_css("figure > em > a > img")["src"]
  end

  test "rich code is normalized to text before rendering or source inspection" do
    %w[ruby invented_language].each do |language|
      body = %(<pre lang="#{language}"><code>start<img src="/hidden.png" alt="Hidden"><strong>end</strong></code></pre>)
      post = OpenBlog::Post.new(body_format: "rich_text")
      post.rich_body = body
      assert_empty OpenBlog::Renderer.document(post).css("img")
      doc = render_body(body, format: :rich_text)
      assert_empty doc.css("img, figure")
      assert_equal "startend", doc.at_css("pre code").text
    end
  end

  test "rich editor preformatted blocks receive code controls and discard embedded media" do
    doc = render_body('<pre lang="ruby">puts &quot;Hello&quot;<img src="/inside.png"></pre>', format: :rich_text)
    assert_equal 'puts "Hello"', doc.at_css("pre code")&.text
    assert doc.at_css("pre button.ob-code-copy")
    assert doc.at_css("pre code span")
    assert_empty doc.css("img, figure")
  end

  test "rich attachments use stored media metadata without storage or database writes" do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("image fixture"), filename: "source.png", content_type: "image/png", identify: false)
    image = OpenBlog::Image.new(sha256: "a" * 64, filename: "stored.png", content_type: "image/png", byte_size: blob.byte_size, width: 24, height: 16)
    image.file = blob
    image.save!
    body = %(<action-text-attachment sgid="#{blob.attachable_sgid}" caption="&lt;em&gt;Leaf detail&lt;/em&gt;" url="https://untrusted.example/source.png"></action-text-attachment>)
    metadata = blob.metadata.deep_dup
    writes = []
    observer = ->(_name, _start, _finish, _id, data) { writes << data[:sql] if data[:sql].match?(/\A\s*(INSERT|UPDATE|DELETE)\b/i) }
    doc = nil
    ActiveSupport::Notifications.subscribed(observer, "sql.active_record") do
      blob.service.stub(:download, ->(*) { flunk "rendering must not download blobs" }) do
        blob.service.stub(:upload, ->(*) { flunk "rendering must not upload blobs" }) do
          doc = render_body(body, format: :rich_text)
        end
      end
    end
    assert_empty writes
    assert_equal metadata, blob.reload.metadata
    assert_equal image.path, doc.at_css("figure img")["src"]
    assert_equal [ "24", "16", "lazy", "Leaf detail" ], %w[width height loading alt].map { |attribute| doc.at_css("img")[attribute] }
    assert_equal "Leaf detail", doc.at_css("figcaption").text
    assert_empty doc.css("action-text-attachment, em")
    refute_includes doc.to_html, "untrusted.example"
  ensure
    blob&.service&.delete(blob.key)
  end

  test "safe output and original heading inspection share the same pipeline" do
    post = OpenBlog::Post.new(body_markdown: "# Original\n\n#### Detail\n")
    fragment = OpenBlog::Renderer.document(post)
    assert_equal %w[h1 h4], fragment.css("h1,h2,h3,h4,h5,h6").map(&:name)
    assert OpenBlog::Renderer.render_string("Safe *text*", format: :markdown).html_safe?
    assert_raises(ArgumentError) { OpenBlog::Renderer.render_string("Text", format: :unsupported) }
  end

  test "the fragment cache follows revision and renderer version rather than metadata timestamps" do
    author = OpenBlog::Author.create!(name: "Riley Garden", slug: "riley-garden")
    post = OpenBlog::Post.create!(title: "Seed notes", slug: "seed-notes", body_markdown: "## Start",
      author: author, author_name: author.name)
    cache = ActiveSupport::Cache::MemoryStore.new
    original_cache = Rails.cache
    Rails.cache = cache
    html = OpenBlog::Renderer.render(post)
    configuration = Digest::SHA256.hexdigest(JSON.generate([ OpenBlog.config.markdown_hardbreaks, OpenBlog.config.public_base_url, OpenBlog.config.locale.to_s ]))
    key = [ "open_blog/body", post.id, post.current_revision_identifier, OpenBlog::Renderer::VERSION, configuration ]
    assert_equal html, cache.read(key)
    post.update!(featured: true)
    OpenBlog::Renderer::Markdown.stub(:render, ->(*) { flunk "cached body should not be recompiled" }) do
      assert_equal html, OpenBlog::Renderer.render(post)
    end
    post.update!(body_markdown: "## New section")
    refute_equal html, OpenBlog::Renderer.render(post)
  ensure
    Rails.cache = original_cache
  end

  private

  def render_body(text, format: :markdown)
    Nokogiri::HTML5.fragment(OpenBlog::Renderer.render_string(text, format: format))
  end
end
