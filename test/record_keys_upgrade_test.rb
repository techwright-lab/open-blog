require_relative "test_helper"
require "minitest/mock"
require "tmpdir"

class RecordKeysUpgradeTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  class UpgradeDatabase < ActiveRecord::Base
    self.abstract_class = true
  end

  ALIGN = "AlignOpenBlogRecordKeys".freeze

  teardown do
    return unless @config
    UpgradeDatabase.remove_connection
    ActiveRecord::Base.connection.drop_database(@config.database) if postgres?
    FileUtils.remove_entry(@directory) if @directory
  end

  test "upgrading a 0.2.0 host with integer attachment records changes nothing" do
    connect
    attachment_table(:bigint)
    run_migrations(except: ALIGN)
    before = schema
    run_migrations(only: ALIGN)
    assert_equal before, schema
    assert_equal :integer, column(:open_blog_images, :id).type
  end

  test "upgrading a 0.2.0 host with UUID attachment records converts blog keys and keeps references" do
    skip "UUID attachment records need PostgreSQL" unless postgres?
    connect
    attachment_table(:uuid)
    OpenBlog::RecordKeys.stub(:attachment_type, :bigint) { run_migrations(except: ALIGN) }
    assert_equal :integer, column(:open_blog_authors, :id).type
    execute "INSERT INTO open_blog_authors (name, slug, created_at, updated_at) VALUES ('Ada', 'ada', now(), now())"
    execute "INSERT INTO open_blog_images (sha256, filename, content_type, byte_size, created_at) VALUES ('#{'a' * 64}', 'a.png', 'image/png', 1, now())"
    execute <<~SQL
      INSERT INTO open_blog_posts (slug, title, body_format, author_id, author_name, cover_image_id, created_at, updated_at)
      SELECT 'note', 'Note', 'markdown', open_blog_authors.id, 'Ada', open_blog_images.id, now(), now()
      FROM open_blog_authors, open_blog_images
    SQL

    run_migrations(only: ALIGN)

    %i[open_blog_authors open_blog_images].each do |table|
      assert_equal :uuid, column(table, :id).type, table
      assert_equal "id", connection.primary_key(table)
    end
    %w[author_id cover_image_id social_image_id].each { |name| assert_equal :uuid, column(:open_blog_posts, name).type, name }
    refute column(:open_blog_posts, :author_id).null
    row = connection.select_one(<<~SQL)
      SELECT open_blog_authors.slug, open_blog_images.filename FROM open_blog_posts
      JOIN open_blog_authors ON open_blog_authors.id = open_blog_posts.author_id
      JOIN open_blog_images ON open_blog_images.id = open_blog_posts.cover_image_id
    SQL
    assert_equal({ "slug" => "ada", "filename" => "a.png" }, row)
    { author_id: :open_blog_authors, cover_image_id: :open_blog_images, social_image_id: :open_blog_images }.each do |name, table|
      assert connection.foreign_key_exists?(:open_blog_posts, table, column: name), name
      assert connection.index_exists?(:open_blog_posts, name), name
    end
    execute "INSERT INTO open_blog_authors (name, slug, created_at, updated_at) VALUES ('Lin', 'lin', now(), now())"
    assert_match OpenBlog::RecordKeys::UUID, connection.select_value("SELECT id FROM open_blog_authors WHERE slug = 'lin'")
  end

  private

  def postgres?
    ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
  end

  def connect
    base = ActiveRecord::Base.connection_db_config.configuration_hash
    @config = if postgres?
      ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "upgrade", base.merge(database: "#{base[:database]}_upgrade_#{Process.pid}"))
    else
      @directory = Dir.mktmpdir("open-blog-upgrade")
      ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "upgrade", base.merge(database: File.join(@directory, "upgrade.sqlite3")))
    end
    ActiveRecord::Base.connection.create_database(@config.database) if postgres?
    UpgradeDatabase.establish_connection(@config)
  end

  def connection
    UpgradeDatabase.connection
  end

  def execute(sql)
    connection.execute(sql)
  end

  def attachment_table(type)
    connection.create_table(:active_storage_attachments, id: type == :uuid ? :uuid : :primary_key) do |t|
      t.string :name, null: false
      t.references :record, null: false, polymorphic: true, index: false, type: type
      t.datetime :created_at, null: false
    end
  end

  def run_migrations(only: nil, except: nil)
    ActiveRecord::MigrationContext.new(OpenBlog::Engine.root.join("db/migrate").to_s).migrations.each do |proxy|
      next if (only && proxy.name != only) || (except && proxy.name == except)
      proxy.send(:migration).tap { |migration| migration.verbose = false }.exec_migration(connection, :up)
    end
  end

  def column(table, name)
    connection.columns(table).find { |candidate| candidate.name == name.to_s }
  end

  def schema
    connection.tables.sort.to_h do |table|
      [ table, { columns: connection.columns(table).map { |c| [ c.name, c.sql_type, c.null, c.default ] },
        indexes: connection.indexes(table).map { |index| [ index.name, index.columns, index.unique ] }.sort,
        foreign_keys: connection.foreign_keys(table).map { |key| [ key.column, key.to_table ] }.sort } ]
    end
  end
end
