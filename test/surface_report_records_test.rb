require_relative "test_helper"
require "minitest/mock"

class SurfaceReportRecordsTest < ActionDispatch::IntegrationTest
  Page = Struct.new(:url, :status, :headers, :body, keyword_init: true) do
    def document = Nokogiri::HTML5(body)
    def article
      document.css('script[type="application/ld+json"]').flat_map { |node| JSON.parse(node.text).fetch("@graph", []) }.find { |entry| %w[BlogPosting Article].include?(entry["@type"]) }
    end
  end

  Context = Struct.new(:posts, :config, :now, :results, :pages, keyword_init: true) do
    def record(predicate, status, reason, post: nil, marks: [], details: nil)
      results << { predicate: predicate, result: status.to_s.tr("_", " "), reason: reason, post_id: post&.id, marks: marks, details: details }
    end
    def row(predicate, post: nil) = results.find { |item| item[:predicate] == predicate && item[:post_id] == post&.id }
    def absolute(path)
      return unless config.public_base_url
      URI.join(config.public_base_url, path).to_s
    end
    def page(url) = pages[url]
    def post_page(post) = page(absolute(post.path))
  end

  setup do
    @settings = %i[policy_urls ai_label].to_h { |key| [ key, OpenBlog.config.public_send(key) ] }
    OpenBlog.config.policy_urls = { responsible_party: "https://example.test/about" }
    OpenBlog.config.ai_label = :when_required
    @now = Time.current.change(usec: 0)
    result = OpenBlog::Publish.call({ title: "Stream guide", description: "Explore the bank.", body: "Watch [the reeds](/habitat).", provenance: "ai_assisted",
      faq: [ { question: "When to visit?", answer: "Early morning." } ], approval: { name: "Avery", facts_checked: true } }, actor: "Editor", now: @now)
    @post = result.post
    get @post.path
    @context = Context.new(posts: [ @post ], config: OpenBlog.config, now: @now, results: [], pages: {})
    @context.pages[@post.url] = Page.new(url: @post.url, status: 200, headers: {}, body: response.body)
    @context.pages[@context.absolute("/blog/sitemap.xml")] = Page.new(status: 200, body: "<urlset><url><loc>#{@post.url}</loc><lastmod>#{@now.iso8601}</lastmod></url></urlset>")
    @context.record("E4", :pass, "Publisher page is available.", post: @post)
  end
  teardown { @settings.each { |key, value| OpenBlog.config.public_send("#{key}=", value) } }

  test "record agreement compares the rendered stored revision and all seven parts" do
    writes = []
    observer = ->(*arguments) { sql = arguments.last[:sql]; writes << sql if sql.match?(/\A\s*(INSERT|UPDATE|DELETE)\b/i) }
    ActiveSupport::Notifications.subscribed(observer, "sql.active_record") do
      OpenBlog::LabelPolicy.stub(:for, ->(*) { flunk "Record checks must not consult label policy" }) { run_checks }
    end
    assert_empty writes
    assert_equal "pass", result("E18")[:result]
    assert_equal "pass", result("E19")[:result], result("E19").inspect
    assert_equal %w[A B C D E F G], result("E19")[:details].keys
    assert_equal "pass", result("E6")[:result]
    assert_equal "not applicable", result("E7")[:result]
    assert_equal "not verified", result("E21")[:result]
    assert_equal "not verified", result("E22")[:result]
  end

  test "a fetched page missing its declared content region fails the content comparison" do
    @context.post_page(@post).body = "<html><head><title>Stream guide</title></head><body>Unavailable content</body></html>"
    run_checks
    assert_equal "fail", result("E19")[:result]
  end

  test "rendered body link head and FAQ drift each fail their independent part" do
    original = @context.post_page(@post).body
    { "B" => [ "Watch", "Ignore" ], "C" => [ 'href="/habitat"', 'href="/other"' ], "F" => [ "<title>Stream guide", "<title>Other guide" ],
      "G" => [ "<p>Early morning.</p>", "<p>After sunset.</p>" ] }.each do |part, (before, after)|
      @context.post_page(@post).body = original.sub(before, after)
      @context.results.reject! { |row| row[:predicate] != "E4" }
      run_checks
      assert_equal "fail", result("E19")[:result], part
      assert_equal "fail", result("E19")[:details][part], part
    end
  end

  test "missing HTTP evidence remains uncertain and missing approval depends on provenance" do
    @context.pages.clear
    OpenBlog::Approval.where(post: @post).delete_all
    run_checks
    assert_equal "fail", result("E18")[:result]
    assert_equal "not verified", result("E19")[:result]
    @post.update_columns(provenance: "unknown")
    @context.results.clear
    run_checks
    assert_equal "not verified", result("E18")[:result]
    assert_equal "not verified", result("E19")[:result]
  end

  test "responsibility evidence is selected for this article rather than another article" do
    @context.results.unshift({ predicate: "E4", result: "fail", post_id: @post.id + 1 })
    run_checks
    assert_equal "not applicable", result("E20")[:result]
  end

  test "report dependency failure requires visible AI notice regardless of local label decision" do
    @context.results.first[:result] = "fail"
    run_checks
    assert_equal "fail", result("E20")[:result]
    @context.post_page(@post).body += '<p class="ob-notice--ai">AI helped to make this post.</p>'
    @context.results.reject! { |row| row[:predicate] != "E4" }
    run_checks
    assert_equal "pass", result("E20")[:result]
  end

  test "declared and later reviews retain truthful record marks" do
    OpenBlog::Approval.where(post: @post).delete_all
    @post.approvals.create!(revision: @post.public_revision, kind: "declared", reviewer_name: "Avery", facts_checked: true,
      approved_at: @now + 1.hour, declared_on: @now.to_date, declared_by: "Publisher")
    run_checks
    assert_equal "pass", result("E18")[:result]
    assert_includes result("E18")[:marks], "publisher declaration"
    assert_includes result("E18")[:marks], "review after release"
    assert_equal @now.iso8601, result("E18")[:details][:released_at]
  end

  test "image list byte digests and social bytes are checked independently" do
    image = OpenBlog::Image.create!(sha256: Digest::SHA256.hexdigest("image bytes"), filename: "bank.png", content_type: "image/png", byte_size: 11, width: 1, height: 1)
    result = OpenBlog::Publish.call({ cover_image: { image_id: image.id }, social_image: { image_id: image.id }, cover_alt: "A river bank", change: "substantive",
      approval: { name: "Avery", facts_checked: true } }, post: @post, actor: "Editor", now: @now)
    assert result.success?, result.error&.message
    @post = result.post
    @context.posts = [ @post ]
    get @post.path
    @context.pages[@post.url].body = response.body
    image_url = "https://storage.example/bank.png"
    @context.pages[@context.absolute(image.path)] = Page.new(status: 302, headers: { "location" => image_url }, body: "")
    @context.pages[image_url] = Page.new(status: 200, body: "image bytes")
    run_checks
    assert_equal "pass", result("E19")[:result], result("E19").inspect
    @context.pages[image_url].body = "changed bytes"
    @context.results.reject! { |row| row[:predicate] != "E4" }
    run_checks
    assert_equal "fail", result("E19")[:details]["E"]
    assert_equal "fail", result("E19")[:details]["F"]
    @context.pages.delete(@context.absolute(image.path))
    @context.results.reject! { |row| row[:predicate] != "E4" }
    run_checks
    assert_equal "not verified", result("E19")[:result]
    doc = @context.post_page(@post).document
    doc.at_css("[data-open-blog-content] img")["alt"] = "Different wording"
    @context.post_page(@post).body = doc.to_html
    @context.results.reject! { |row| row[:predicate] != "E4" }
    run_checks
    assert_equal "fail", result("E19")[:details]["D"]
  end

  test "structured and sitemap modification drift cannot be hidden by correct model dates" do
    @context.pages[@context.absolute("/blog/sitemap.xml")].body = "<urlset><url><loc>#{@post.url}</loc><lastmod>2001-01-01</lastmod></url></urlset>"
    run_checks
    assert_equal "fail", result("E6")[:result]
  end

  test "offsite canonical articles need no sitemap modification entry and malformed XML cannot pass" do
    @post.update_columns(canonical_url: "https://original.example/stream-guide")
    @context.pages[@context.absolute("/blog/sitemap.xml")].body = "<urlset/>"
    run_checks
    assert_equal "pass", result("E6")[:result]
    @context.pages[@context.absolute("/blog/sitemap.xml")].body = "<urlset>"
    @context.results.clear
    run_checks
    assert_equal "fail", result("E6")[:result]
  end

  test "unavailable redirect evidence is not a failed response" do
    OpenBlog::Redirect.create!(old_path: "/blog/old-bank", new_path: @post.path, source: "manual", occurred_on: @now.to_date)
    @context.pages[@context.absolute("/blog/old-bank")] = Page.new(status: 0, body: "")
    run_checks
    assert_equal "not verified", @context.row("T4")[:result]
  end

  test "altering stored content without a release fails record identity even with an unchanged public page" do
    @post.update_columns(body_markdown: "Unrecorded replacement.")
    run_checks
    assert_equal "fail", result("E19")[:details]["A"]
  end

  test "unknown adopted modification date stays uncertain and declarations of none are explicit" do
    @post.create_baseline!(adopted_revision: @post.public_revision, adopted_at: @now, provenance: "ai_assisted")
    @post.connection_declarations.create!(connections: [], third_party_paid: false, declared_by: "Avery", declared_on: @now.to_date)
    run_checks
    assert_equal "not verified", result("E6")[:result]
    assert_equal "not applicable", result("E21")[:result]
    assert_equal "not applicable", result("E22")[:result]
  end

  test "declared connections and corrections require fetched disclosure markup" do
    @post.connection_declarations.create!(connections: [ { party: "Nursery", relation: "Provided plants" } ], third_party_paid: true,
      declared_by: "Avery", declared_on: @now.to_date)
    OpenBlog::Publish.call({ change: "correction", note: "The planting month was corrected." }, post: @post, actor: "Editor", now: @now)
    run_checks
    %w[E7 E21 E22].each { |predicate| assert_equal "fail", result(predicate)[:result] }
    get @post.path
    @context.post_page(@post).body = response.body
    @context.results.reject! { |row| row[:predicate] != "E4" }
    run_checks
    %w[E7 E21 E22].each { |predicate| assert_equal "pass", result(predicate)[:result] }
  end

  test "hidden notices and disclosure blocks do not supply visible evidence" do
    @post.connection_declarations.create!(connections: [ { party: "Nursery", relation: "Provided plants" } ], third_party_paid: true,
      declared_by: "Avery", declared_on: @now.to_date)
    OpenBlog::Publish.call({ change: "correction", note: "The planting month was corrected." }, post: @post, actor: "Editor", now: @now)
    get @post.path
    @context.post_page(@post).body = response.body
    @context.results.first[:result] = "fail"
    %w[hidden aria-hidden].product(%i[self ancestor]).each do |attribute, placement|
      document = Nokogiri::HTML5(response.body)
      document.at_css("[data-open-blog-content]").add_child('<p class="ob-notice--ai">AI helped to make this post.</p>')
      nodes = placement == :self ? document.css(".ob-notice--ai, .ob-correction, .ob-disclosure, .ob-notice--paid") : document.css("[data-open-blog-content]")
      nodes.each { |node| node[attribute] = attribute == "hidden" ? "hidden" : "true" }
      @context.post_page(@post).body = document.to_html
      @context.results.reject! { |row| row[:predicate] != "E4" }
      run_checks
      %w[E7 E20 E21 E22].each { |predicate| assert_equal "fail", result(predicate)[:result], "#{predicate} #{attribute} #{placement}" }
    end
  end

  test "invalid structured date shapes fail the date check without aborting the report" do
    document = @context.post_page(@post).document
    node = document.css('script[type="application/ld+json"]').find { |entry| entry.text.include?("dateModified") }
    json = JSON.parse(node.text)
    json.fetch("@graph").find { |entry| entry["dateModified"] }["dateModified"] = { "value" => @now.iso8601 }
    node.content = JSON.generate(json)
    @context.post_page(@post).body = document.to_html
    run_checks
    assert_equal "fail", result("E6")[:result]
  end

  test "redirect records require the exact one step destination or a removal response" do
    moved = OpenBlog::Redirect.create!(old_path: "/blog/old-stream", new_path: @post.path, source: "manual", occurred_on: @now.to_date)
    removed = OpenBlog::Redirect.create!(old_path: "/blog/closed-stream", source: "manual", occurred_on: @now.to_date)
    @context.pages[@context.absolute(moved.old_path)] = Page.new(status: 301, headers: { "location" => @post.url }, body: "")
    @context.pages[@context.absolute(removed.old_path)] = Page.new(status: 410, headers: {}, body: "")
    run_checks
    assert_equal [ "pass", "pass" ], @context.results.select { |row| row[:predicate] == "T4" }.pluck(:result)
    @context.pages[@context.absolute(moved.old_path)].headers["location"] = "/blog/intermediate"
    @context.results.clear
    run_checks
    assert_equal [ "fail", "pass" ], @context.results.select { |row| row[:predicate] == "T4" }.pluck(:result)
  end

  private

  def run_checks
    OpenBlog::SurfaceReport::RecordChecks.new(@context).call
  end

  def result(predicate) = @context.row(predicate, post: @post)
end
