require_relative "test_helper"

class SearchTest < ActiveSupport::TestCase
  test "search covers title description body and FAQ while respecting the supplied scope" do
    title = publish(title: "Kingfisher sightings")
    description = publish(description: "Waterside habitat")
    body = publish(body: "Reeds shelter dragonflies.")
    faq = publish(faq: [ { question: "What grows here?", answer: "Watermint grows beside the stream." } ])
    draft = save(title: "Kingfisher draft")
    scheduled = save(title: "Kingfisher scheduled")
    scheduled.update!(status: "scheduled", publish_at: 1.day.from_now)
    { "kingfisher" => title, "waterside" => description, "dragonflies" => body, "watermint" => faq }.each do |query, post|
      assert_equal [ post.id ], OpenBlog::Search.call(query).pluck(:id)
    end
    assert_equal [ draft.id ], OpenBlog::Search.call("kingfisher", scope: OpenBlog::Post.where(id: draft.id)).pluck(:id)
  end

  test "invalid query shapes and trimmed lengths return empty relations" do
    post = publish(title: "Reed beds")
    [ nil, [], {}, 12, "", "   ", "a", "x" * 101 ].each do |query|
      assert_empty OpenBlog::Search.call(query), query.inspect
    end
    assert_equal [ post.id ], OpenBlog::Search.call("  REED  ").pluck(:id)
    post.update_columns(search_text: "x" * 100)
    assert_equal [ post.id ], OpenBlog::Search.call("x" * 100).pluck(:id)
  end

  test "all words match irrespective of order and limit preserves deterministic newest ties" do
    old = publish(body: "River banks contain reeds.")
    newer = publish(body: "River banks contain reeds.")
    publish(body: "River banks are bare.")
    old.update_columns(created_at: 2.days.ago)
    newer.update_columns(created_at: 1.day.ago)
    assert_equal [ newer.id, old.id ], OpenBlog::Search.call("reeds river").pluck(:id)
    assert_equal [ newer.id ], OpenBlog::Search.call("reeds river", limit: 1).pluck(:id)
  end

  test "PostgreSQL uses word boundaries websearch operators and relevance before recency" do
    skip "PostgreSQL full text search" unless postgres?
    strong = publish(body: "Heron heron heron heron heron.")
    weak = publish(body: "A heron crosses the river past the trees.")
    publish(body: "Heronry beside the river.")
    strong.update_columns(created_at: 2.days.ago)
    assert_equal [ strong.id, weak.id ], OpenBlog::Search.call("heron").pluck(:id)
    assert_equal [ strong.id ], OpenBlog::Search.call("heron -river").pluck(:id)
    assert_equal [ weak.id ], OpenBlog::Search.call('"crosses the river"').pluck(:id)
  end

  test "SQLite LIKE treats wildcard and escape characters literally" do
    skip "SQLite LIKE fallback" if postgres?
    literal = publish(body: 'Marker 50%_\\edge remains.')
    publish(body: "Marker 500xedge remains.")
    assert_equal [ literal.id ], OpenBlog::Search.call('50%_\\edge').pluck(:id)
  end

  test "API omitted query lists drafts while explicit blank or short queries are empty" do
    draft = save(title: "Marsh notes")
    assert_equal [ draft.id ], OpenBlog::ApiPostQuery.call({})[:posts].pluck(:id)
    [ "", " ", "a", "x" * 101 ].each do |query|
      assert_equal 0, OpenBlog::ApiPostQuery.call({ q: query })[:total]
    end
    assert_equal [ draft.id ], OpenBlog::ApiPostQuery.call({ q: "marsh" })[:posts].pluck(:id)
  end

  test "API search composes all taxonomy filters without duplicate counts and preserves pagination" do
    attributes = { body: "Reeds shelter birds.", category: "Wetlands", tags: [ "Water", "Plants" ], series: "Habitats", author: { name: "Morgan" } }
    first = save(**attributes.merge(series_position: 1))
    second = save(**attributes.merge(series_position: 2))
    save(body: "Reeds shelter birds.")
    filters = { q: "birds reeds", category: "wetlands", tag: "water", series: "habitats", author: first.author.slug, per_page: 1 }
    result = OpenBlog::ApiPostQuery.call(filters)
    assert_equal 2, result[:total]
    assert_equal [ second.id ], result[:posts].pluck(:id)
    assert_equal [ first.id ], OpenBlog::ApiPostQuery.call(filters.merge(page: 2))[:posts].pluck(:id)
  end

  private

  def postgres?
    ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
  end

  def save(**attributes)
    result = OpenBlog::SaveDraft.call({ title: "Field note #{SecureRandom.hex(4)}", body: "Observations beside the stream." }.merge(attributes), actor: "Editor")
    assert result.success?, result.error&.message
    result.post
  end

  def publish(**attributes)
    post = save(**attributes)
    result = OpenBlog::Publish.call({}, post: post, actor: "Editor")
    assert result.success?, result.error&.message
    result.post
  end
end
