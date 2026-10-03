require_relative "test_helper"

class FindingsTest < ActiveSupport::TestCase
  setup do
    @author = OpenBlog::Author.create!(name: "Taylor Brook", slug: "taylor-brook")
    @original_policy = OpenBlog.config.policy_urls.dup
    @original_primary = OpenBlog.config.primary_list_type
    @original_image = OpenBlog.config.default_social_image_url
    @original_base = OpenBlog.config.public_base_url
    OpenBlog.config.policy_urls[:responsible_party] = nil
    OpenBlog.config.primary_list_type = :categories
    OpenBlog.config.default_social_image_url = nil
    OpenBlog.config.public_base_url = "https://journal.example"
  end

  teardown do
    OpenBlog.config.policy_urls = @original_policy
    OpenBlog.config.primary_list_type = @original_primary
    OpenBlog.config.default_social_image_url = @original_image
    OpenBlog.config.public_base_url = @original_base
  end

  test "basic findings are structured advisory values without database writes" do
    post = create_post(status: "published")
    before = [ OpenBlog::Post.count, OpenBlog::Revision.count, OpenBlog::Publication.count, OpenBlog::Approval.count ]
    findings = OpenBlog::Findings.for(post)
    expected = %i[description_absent category_absent provenance_unknown approval_absent connections_not_declared responsible_party_absent social_image_absent]
    assert_equal expected.sort, findings.map { |finding| finding[:code] }.sort
    findings.each do |finding|
      assert_equal %i[code location message rule], finding.keys.sort
      assert finding[:message].present?
    end
    assert_equal "T8", findings.find { |finding| finding[:code] == :description_absent }[:rule]
    assert_equal before, [ OpenBlog::Post.count, OpenBlog::Revision.count, OpenBlog::Publication.count, OpenBlog::Approval.count ]
  end

  test "description presence checks both editorial and search descriptions" do
    post = create_post
    assert_includes codes(post), :description_absent
    post.description = "An introduction to seedlings."
    refute_includes codes(post), :description_absent
    post.description = ""
    post.search_description = "A search snippet about seedlings."
    refute_includes codes(post), :description_absent
  end

  test "duplicates use other listed posts and effective meta descriptions" do
    post = create_post(title: "Seedling notes", description: "Editorial introduction", search_description: "Search introduction")
    other = create_post(title: post.title, description: "Search introduction", status: "draft")
    refute_includes codes(post), :title_duplicate
    refute_includes codes(post), :description_duplicate
    other.update!(status: "published")
    assert_includes codes(post), :title_duplicate
    assert_includes codes(post), :description_duplicate
    refute_includes codes(other), :title_duplicate
    other.update!(title: "Different title", search_description: "Another search introduction")
    refute_includes codes(post), :title_duplicate
    refute_includes codes(post), :description_duplicate
    assert_includes codes(other), :category_absent
  end

  test "a lone published post does not duplicate itself or empty descriptions" do
    post = create_post(status: "published")
    refute_includes codes(post), :title_duplicate
    refute_includes codes(post), :description_duplicate
    create_post(status: "published")
    refute_includes codes(post), :description_duplicate
  end

  test "category checks follow the configured primary list type" do
    post = create_post
    assert_includes codes(post), :category_absent
    post.category = OpenBlog::Category.create!(name: "Field notes", slug: "field-notes")
    refute_includes codes(post), :category_absent
    assert_includes codes(post), :category_description_absent
    post.category.description = "Notes recorded outdoors."
    refute_includes codes(post), :category_description_absent
    post.category.description = nil
    OpenBlog.config.primary_list_type = :tags
    refute_includes codes(post), :category_description_absent
    post.category = nil
    refute_includes codes(post), :category_absent
  end

  test "FAQ checks inspect current entries and locate duplicate questions and markup" do
    post = create_post
    post.faqs.build(position: 1, question: "How much water?", answer: "One cup.")
    duplicate = post.faqs.build(position: 2, question: "How much water?", answer: "Use **clean** water.")
    findings = OpenBlog::Findings.for(post)
    assert_equal "faq[1].question", findings.find { |finding| finding[:code] == :faq_question_duplicate }[:location]
    assert_equal "faq[1].answer", findings.find { |finding| finding[:code] == :faq_markup_in_answer }[:location]
    duplicate.mark_for_destruction
    refute_includes codes(post), :faq_question_duplicate
    refute_includes codes(post), :faq_markup_in_answer
    post.faqs.first.answer = "<em>Water</em> slowly."
    assert_includes codes(post), :faq_markup_in_answer
    post.faqs.first.answer = "Use 2 * 3 cups when 4 < 5."
    refute_includes codes(post), :faq_markup_in_answer
  end

  test "request findings need explicit context and are not inferred from stored identity" do
    post = create_post(author_name: OpenBlog.config.default_author[:name])
    defaults = codes(post)
    %i[author_default_used slug_changed approval_incomplete].each { |code| refute_includes defaults, code }
    findings = OpenBlog::Findings.for(post, context: { author_default_used: true, slug_changed: true, approval_incomplete: true })
    %i[author_default_used slug_changed approval_incomplete].each do |code|
      assert_includes findings.map { |finding| finding[:code] }, code
    end
  end

  test "provenance and qualifying approval findings follow the relevant revision" do
    post = create_post(status: "published", provenance: "ai_assisted")
    refute_includes codes(post), :provenance_unknown
    assert_includes codes(post), :approval_absent
    post.approvals.create!(revision: post.public_revision, kind: "sent", reviewer_name: "Reviewer",
      facts_checked: false, approved_at: Time.current)
    assert_includes codes(post), :approval_absent
    post.approvals.create!(revision: post.public_revision, kind: "sent", reviewer_name: "Reviewer",
      facts_checked: true, approved_at: Time.current)
    refute_includes codes(post), :approval_absent
    post.update!(body_markdown: "A revised recommendation.")
    assert_includes codes(post), :approval_absent
    post.provenance = "human_written"
    refute_includes codes(post), :approval_absent
  end

  test "scheduled approvals bind to current content rather than the last public revision" do
    post = create_post(status: "scheduled", provenance: "ai_assisted")
    assert_includes codes(post), :approval_absent
    revision = post.revisions.create!(identifier: post.current_revision_identifier,
      payload: OpenBlog::RevisionPayload.new(post).to_json)
    post.approvals.create!(revision: revision, kind: "sent", reviewer_name: "Reviewer",
      facts_checked: true, approved_at: Time.current)
    refute_includes codes(post), :approval_absent
    post.update!(body_markdown: "A changed schedule draft.")
    assert_includes codes(post), :approval_absent
    post.status = "draft"
    refute_includes codes(post), :approval_absent
  end

  test "explicit connection declarations and responsible party URLs clear their findings" do
    post = create_post
    assert_includes codes(post), :connections_not_declared
    post.connection_declarations.create!(connections: [], third_party_paid: false,
      declared_by: "Editor", declared_on: Date.current)
    refute_includes codes(post), :connections_not_declared
    assert_includes codes(post), :responsible_party_absent
    OpenBlog.config.policy_urls[:responsible_party] = "https://journal.example/editor"
    refute_includes codes(post), :responsible_party_absent
  end

  test "canonical URLs distinguish the configured origin without fetching it" do
    post = create_post(canonical_url: "https://journal.example/original")
    refute_includes codes(post), :canonical_off_site
    post.canonical_url = "https://publisher.example/original"
    assert_includes codes(post), :canonical_off_site
    OpenBlog.config.public_base_url = nil
    refute_includes codes(post), :canonical_off_site
  end

  test "cover social or configured images clear the image finding" do
    post = create_post
    assert_includes codes(post), :social_image_absent
    OpenBlog.config.default_social_image_url = "https://journal.example/default.png"
    refute_includes codes(post), :social_image_absent
    OpenBlog.config.default_social_image_url = nil
    image = OpenBlog::Image.create!(sha256: "c" * 64, filename: "tree.png", content_type: "image/png", byte_size: 12)
    post.cover_image = image
    refute_includes codes(post), :social_image_absent
    post.cover_image = nil
    post.social_image = image
    refute_includes codes(post), :social_image_absent
  end

  test "registries accept additional checks without changing the default registry" do
    registry = OpenBlog::Findings::Registry.new
    check = OpenBlog::Findings::Check.new(code: :custom_notice, rule: nil,
      message: "The title is brief.", location: "title") { |post, _context| post.title.length < 30 }
    registry.register(check)
    post = create_post
    assert_equal [ :custom_notice ], registry.for(post).map { |finding| finding[:code] }
    registry.register(check)
    assert_equal 1, registry.for(post).length
    refute_includes codes(post), :custom_notice
  end

  private

  def codes(post)
    OpenBlog::Findings.for(post).map { |finding| finding[:code] }
  end

  def create_post(**attributes)
    OpenBlog::Post.create!({ title: "Seedbed preparation", slug: "seedbed-#{OpenBlog::Post.count}",
      author: @author, author_name: @author.name, body_markdown: "Prepare a level bed." }.merge(attributes))
  end
end
