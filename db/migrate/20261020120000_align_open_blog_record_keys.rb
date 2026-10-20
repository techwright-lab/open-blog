class AlignOpenBlogRecordKeys < ActiveRecord::Migration[8.0]
  REFERENCES = {
    open_blog_authors: { author_id: false },
    open_blog_images: { cover_image_id: true, social_image_id: true }
  }.freeze

  def up
    return unless OpenBlog::RecordKeys.attachment_type(connection) == :uuid
    REFERENCES.each { |table, columns| convert(table, columns) unless key_type(table) == :uuid }
  end

  # Keys converted to UUID match the attachment table, as the create migrations now make them.
  def down
  end

  private

  def key_type(table)
    connection.columns(table).find { |column| column.name == "id" }.type
  end

  def convert(table, columns)
    add_column table, :uuid_id, :uuid, null: false, default: -> { "gen_random_uuid()" }
    columns.each do |column, nullable|
      remove_foreign_key :open_blog_posts, column: column
      add_column :open_blog_posts, "#{column}_uuid", :uuid
      execute <<~SQL.squish
        UPDATE open_blog_posts SET #{column}_uuid = #{table}.uuid_id
        FROM #{table} WHERE #{table}.id = open_blog_posts.#{column}
      SQL
      remove_column :open_blog_posts, column
      rename_column :open_blog_posts, "#{column}_uuid", column
      change_column_null :open_blog_posts, column, false unless nullable
      add_index :open_blog_posts, column
    end
    remove_column table, :id
    rename_column table, :uuid_id, :id
    execute "ALTER TABLE #{table} ADD PRIMARY KEY (id)"
    columns.each_key { |column| add_foreign_key :open_blog_posts, table, column: column }
  end
end
