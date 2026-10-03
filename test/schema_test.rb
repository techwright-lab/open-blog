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

  test "database rejects case equivalent tag names even without model validation" do
    insert_tag("Rails", "rails")
    assert_raises(ActiveRecord::RecordNotUnique) do
      ActiveRecord::Base.transaction(requires_new: true) { insert_tag("rails", "rails-again") }
    end
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
