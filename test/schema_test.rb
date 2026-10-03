require_relative "test_helper"

class SchemaTest < ActiveSupport::TestCase
  TABLES = %w[authors categories series images posts faqs tags taggings redirects revisions approvals publications baselines connection_declarations].freeze

  test "all content tables exist with primary keys and creation times" do
    TABLES.each do |name|
      table = "open_blog_#{name}"
      assert connection.table_exists?(table), table
      assert_equal "id", connection.primary_key(table)
      refute connection.columns(table).find { |column| column.name == "created_at" }.null
    end
  end

  test "mutable tables alone have update timestamps" do
    mutable = %w[authors categories series posts faqs redirects]
    TABLES.each do |name|
      assert_equal mutable.include?(name), connection.column_exists?("open_blog_#{name}", :updated_at), name
    end
  end

  test "structured columns use native adapter JSON types" do
    expected = connection.adapter_name == "PostgreSQL" ? :jsonb : :json
    assert_equal expected, connection.columns(:open_blog_authors).find { |column| column.name == "profile_urls" }.type
    assert_equal expected, connection.columns(:open_blog_connection_declarations).find { |column| column.name == "connections" }.type
    assert_equal expected, connection.columns(:open_blog_posts).find { |column| column.name == "body_image_manifest" }.type
  end

  test "policy pages have no seeded content and only an update timestamp" do
    columns = connection.columns(:open_blog_pages).index_by(&:name)
    assert_equal %w[approved_by approved_on body_markdown id kind slug status title updated_at], columns.keys.sort
    assert_equal "", columns.fetch("body_markdown").default
    assert_equal "draft", columns.fetch("status").default
    %w[kind slug title body_markdown status updated_at].each { |name| refute columns.fetch(name).null }
    assert columns.fetch("approved_by").null
    assert columns.fetch("approved_on").null
    unique = connection.indexes(:open_blog_pages).select(&:unique).map(&:columns)
    assert_includes unique, [ "kind" ]
    assert_includes unique, [ "slug" ]
  end

  test "database rejects case equivalent tag names even without model validation" do
    insert_tag("Rails", "rails")
    assert_raises(ActiveRecord::RecordNotUnique) do
      ActiveRecord::Base.transaction(requires_new: true) { insert_tag("rails", "rails-again") }
    end
  end

  test "page view rows contain only a post day and count" do
    columns = connection.columns(:open_blog_page_views).index_by(&:name)
    assert_equal %w[day id post_id views], columns.keys.sort
    %w[post_id day views].each { |name| refute columns.fetch(name).null }
    assert_equal "0", columns.fetch("views").default.to_s
    assert connection.foreign_key_exists?(:open_blog_page_views, :open_blog_posts, column: :post_id)
    indexes = connection.indexes(:open_blog_page_views)
    assert indexes.any? { |index| index.unique && index.columns == %w[post_id day] }
    assert indexes.any? { |index| index.columns == [ "day" ] }
  end

  test "database enforces unique keys used by content operations" do
    expected = {
      authors: [ [ "slug" ] ], categories: [ [ "name" ], [ "slug" ] ], series: [ [ "slug" ] ],
      images: [ [ "sha256" ] ], posts: [ [ "slug" ], [ "external_id" ], [ "series_id", "series_position" ] ],
      faqs: [ [ "post_id", "position" ] ], tags: [ [ "slug" ] ], taggings: [ [ "post_id", "tag_id" ] ],
      redirects: [ [ "old_path" ] ], revisions: [ [ "post_id", "identifier" ] ],
      baselines: [ [ "post_id" ], [ "source_system", "source_id" ] ]
    }
    expected.each do |table, indexes|
      actual = connection.indexes("open_blog_#{table}").select(&:unique).map(&:columns)
      indexes.each { |columns| assert_includes actual, columns, "#{table}: #{columns}" }
    end
  end

  test "public revision foreign key and conditional first publication uniqueness exist" do
    assert connection.foreign_key_exists?(:open_blog_posts, :open_blog_revisions, column: :public_revision_id)
    index = connection.indexes(:open_blog_publications).find { |candidate| candidate.name == "index_open_blog_publications_first" }
    assert index.unique
    assert_equal [ "post_id" ], index.columns
    assert_match(/entry_type.*first/, index.where)
  end

  test "search index exists only on PostgreSQL" do
    index = connection.indexes(:open_blog_posts).find { |candidate| candidate.name == "index_open_blog_posts_search" }
    if connection.adapter_name == "PostgreSQL"
      assert_equal :gin, index.using
      assert_match(/to_tsvector/, index.columns)
    else
      assert_nil index
    end
  end

  private
    def connection
      ActiveRecord::Base.connection
    end

    def insert_tag(name, slug)
      connection.execute("INSERT INTO open_blog_tags (name, slug, created_at) VALUES (#{connection.quote(name)}, #{connection.quote(slug)}, CURRENT_TIMESTAMP)")
    end
end
