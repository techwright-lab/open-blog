class CreateOpenBlogTags < ActiveRecord::Migration[8.0]
  def change
    create_table :open_blog_tags do |t|
      t.string :name, null: false, **(connection.adapter_name == "SQLite" ? { collation: "NOCASE" } : {})
      t.string :slug, null: false
      t.datetime :created_at, null: false
    end
    add_index :open_blog_tags, connection.adapter_name == "PostgreSQL" ? "lower(name)" : :name, unique: true, name: "index_open_blog_tags_on_name"
    add_index :open_blog_tags, :slug, unique: true
    create_table :open_blog_taggings do |t|
      t.references :post, null: false, foreign_key: { to_table: :open_blog_posts }
      t.references :tag, null: false, foreign_key: { to_table: :open_blog_tags }
      t.datetime :created_at, null: false
    end
    add_index :open_blog_taggings, [ :post_id, :tag_id ], unique: true
  end
end
