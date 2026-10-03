require_relative "test_helper"

class OperationInputsTest < ActiveSupport::TestCase
  test "results and domain errors have stable independent defaults" do
    result = OpenBlog::Result.new
    assert result.success?
    assert_equal({ revision: nil, publication: nil, approval: nil }, result.records)
    assert_equal :ai_unknown, result.label
    refute result.dry_run
    result.records[:revision] = "new"
    assert_nil OpenBlog::Result.new.records[:revision]
    error = OpenBlog::Error::ChangeTypeRequired.new(details: [ "change" ])
    assert_equal :change_type_required, error.code
    assert_equal 422, error.status
    assert_equal [ "change" ], error.details
    refute OpenBlog::Result.new(error: error).success?
    assert_equal 409, OpenBlog::Error::IdentityConflict.new.status
  end

  test "identity resolves external ids and detects conflicting slugs while explicit posts win" do
    first = create_post("first", external_id: "item-a")
    second = create_post("second", external_id: "item-b")
    assert_equal first, OpenBlog::PostIdentity.resolve({ external_id: "item-a" })
    assert_equal second, OpenBlog::PostIdentity.resolve({ external_id: "item-a" }, post: second)
    assert_raises(OpenBlog::Error::IdentityConflict) do
      OpenBlog::PostIdentity.resolve({ external_id: "item-a", slug: "second" })
    end
    assert OpenBlog::PostIdentity.resolve({ title: "Unstored" }).new_record?
  end

  test "identity protects route segments and redirected paths but permits their owner" do
    post = create_post("current")
    OpenBlog::Redirect.create!(old_path: "#{OpenBlog.mount_path}/earlier", new_path: post.path, post: post, source: "slug_change", occurred_on: Date.current)
    [ "feed", OpenBlog.config.route_segments.values.first, "earlier" ].each do |slug|
      assert_raises(OpenBlog::Error::SlugReserved) { OpenBlog::PostIdentity.resolve({ slug: slug }) }
    end
    assert_equal post, OpenBlog::PostIdentity.resolve({ slug: "earlier" }, post: post)
  end

  test "assignment builds default author and slug without saving the post" do
    post = OpenBlog::Post.new
    assign(post, title: "A Field Notebook", body: "First note.")
    assert post.new_record?
    assert_equal "a-field-notebook", post.slug
    assert_equal OpenBlog.config.default_author[:name], post.author_name
    assert post.author.persisted?
    assert_equal "First note.", post.body_markdown
    assert_equal "unknown", post.provenance
    unusual = OpenBlog::Post.new
    assign(unusual, title: "🌲")
    assert_match(/\Apost-[0-9a-f]{12}\z/, unusual.slug)
  end

  test "partial content and author copies survive later profile renames" do
    post = create_post("notebook", description: "Keep me")
    original_name = post.author_name
    post.author.update!(name: "Renamed Writer")
    assign(post, body: "Another entry")
    assert_equal "Keep me", post.description
    assert_equal original_name, post.author_name
    assign(post, author: post.author.slug)
    assert_equal "Renamed Writer", post.author_name
    assign(post, author: { name: "Garden Group", type: "organization", url: "https://garden.example" })
    assert_equal "organization", post.author.author_type
    assert_equal "Garden Group", post.author_name
  end

  test "taxonomy and FAQ values replace lists and preserve unsaved child content" do
    post = create_post("taxonomy")
    post.faqs.create!(question: "Old question?", answer: "Old answer", position: 1)
    assign(post, category: "Garden Notes", series: "Seasonal Work", series_position: 2,
      tags: [ "Soil", "soil", "Seeds" ], faq: [ { question: "New question?", answer: "New answer" } ])
    assert_equal "Garden Notes", post.category.name
    assert_equal "Seasonal Work", post.series.name
    assert_equal [ "Seeds", "Soil" ], post.tags.map(&:name).sort
    assert_equal [ { question: "New question?", answer: "New answer" } ], post.faq_list
    assert_equal "Old answer", post.faqs.where(question: "Old question?").pick(:answer)
    post.save!
    assert_equal [ "New answer" ], post.reload.faqs.pluck(:answer)
    assign(post, faq: [], tags: [], category: nil, series: nil)
    post.save!
    assert_empty post.reload.faqs
    assert_empty post.tags
    assert_nil post.category
    assert_nil post.series
  end

  test "image references preserve existing records and empty canonical values clear" do
    post = create_post("picture", canonical_url: "https://garden.example/notes")
    image = OpenBlog::Image.create!(sha256: "a" * 64, filename: "leaf.png", content_type: "image/png", byte_size: 5)
    assign(post, cover_image: { image_id: image.id }, social_image: image, canonical_url: "")
    assert_equal image, post.cover_image
    assert_equal image, post.social_image
    assert_nil post.canonical_url
    assign(post, cover_image: nil)
    assert_nil post.cover_image
  end

  test "provenance changes retain explicit evidence or record the actor and time" do
    post = create_post("evidence")
    assign(post, provenance: "ai_assisted", provenance_evidence: "Draft tool output")
    assert_equal "Draft tool output", post.provenance_evidence
    assign(post, provenance: "human_written")
    assert_equal "Stated by editor in the call of 2026-10-03T12:00:00Z", post.provenance_evidence
    assign(post, title: "Another title")
    assert_equal "Stated by editor in the call of 2026-10-03T12:00:00Z", post.provenance_evidence
  end

  test "unknown fields disabled formats and malformed typed values are refused" do
    post = OpenBlog::Post.new
    error = assert_raises(OpenBlog::Error::UnknownField) { assign(post, status: "published") }
    assert_equal [ "status" ], error.details
    assert_raises(OpenBlog::Error::BodyFormatNotPermitted) { assign(post, body_format: "rich_text") }
    [ { faq: {} }, { faq: [ { question: "Question?" } ] }, { tags: "soil" },
      { featured: "false" }, { title: [] }, { series_position: "2" }, { author: {} },
      { provenance: "fiction" } ].each do |attributes|
      assert_raises(OpenBlog::Error::ValidationFailed, attributes.inspect) { assign(post, **attributes) }
    end
  end

  test "string keys author IDs and rich text inputs are mapped explicitly" do
    post = create_post("format")
    author = OpenBlog::Author.create!(name: "Other Writer", slug: "other-writer")
    assign(post, author: author.id.to_s)
    assert_equal author, post.author
    original_formats = OpenBlog.config.body_formats
    OpenBlog.config.body_formats = [ :markdown, :rich_text ]
    OpenBlog::PostAttributes.assign(post, { "body_format" => "rich_text", "body" => "<p>New leaf</p>" }, actor: "editor", now: Time.current)
    assert_equal "rich_text", post.body_format
    assert_includes post.body_for_payload, "New leaf"
    assert_raises(OpenBlog::Error::ImageNotPermitted) { assign(post, cover_image: { url: "https://garden.example/leaf.png" }) }
    assert_raises(OpenBlog::Error::ImageNotPermitted) { assign(post, social_image: { signed_id: "blob-token" }) }
    assert_raises(OpenBlog::Error::NotFound) { assign(post, author: 999_999_999) }
  ensure
    OpenBlog.config.body_formats = original_formats if original_formats
  end

  test "null optional text clears content without violating database constraints" do
    post = create_post("clear", description: "Prior description", search_title: "Prior search title")
    assign(post, description: nil, search_title: nil, search_description: nil, cover_alt: nil)
    post.save!
    assert_equal [ "", "", "", "" ], post.reload.attributes.values_at("description", "search_title", "search_description", "cover_alt")
  end

  test "identity rejects nontext identity values before querying" do
    assert_raises(OpenBlog::Error::ValidationFailed) { OpenBlog::PostIdentity.resolve({ external_id: [] }) }
    assert_raises(OpenBlog::Error::ValidationFailed) { OpenBlog::PostIdentity.resolve({ slug: {} }) }
  end

  private

  def assign(post, **attributes)
    OpenBlog::PostAttributes.assign(post, attributes, actor: "editor", now: Time.utc(2026, 10, 3, 12))
  end

  def create_post(slug, **attributes)
    author = OpenBlog::Author.find_or_create_by!(slug: "local-writer") { |record| record.name = "Local Writer" }
    OpenBlog::Post.create!({ title: slug.titleize, slug: slug, author: author, author_name: author.name }.merge(attributes))
  end
end
