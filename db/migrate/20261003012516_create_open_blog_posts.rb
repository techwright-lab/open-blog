class CreateOpenBlogPosts < ActiveRecord::Migration[8.0]
  def change
    create_table :open_blog_posts do |t|
      t.string :slug, null: false
      t.string :title, null: false
      t.text :description, null: false, default: ""
      t.string :search_title, null: false, default: ""
      t.text :search_description, null: false, default: ""
      t.string :body_format, null: false
      t.text :body_markdown
      t.references :author, null: false, foreign_key: { to_table: :open_blog_authors }
      t.string :author_name, null: false
      t.references :category, foreign_key: { to_table: :open_blog_categories }
      t.references :series, foreign_key: { to_table: :open_blog_series }
      t.integer :series_position
      t.string :status, null: false, default: "draft"
      t.datetime :published_at
      t.datetime :modified_at
      t.datetime :publish_at
      t.string :provenance, null: false, default: "unknown"
      t.text :provenance_evidence
      t.boolean :featured, null: false, default: false
      t.string :canonical_url, limit: 2048
      t.string :external_id
      t.references :cover_image, foreign_key: { to_table: :open_blog_images }
      t.string :cover_alt, null: false, default: ""
      t.references :social_image, foreign_key: { to_table: :open_blog_images }
      t.string :current_revision_identifier, limit: 64
      t.references :public_revision
      t.integer :word_count, null: false, default: 0
      t.integer :reading_time_minutes, null: false, default: 1
      t.text :search_text
      t.timestamps
    end
    add_index :open_blog_posts, :slug, unique: true
    add_index :open_blog_posts, :external_id, unique: true
    add_index :open_blog_posts, [ :status, :published_at ]
    add_index :open_blog_posts, [ :status, :publish_at ]
    add_index :open_blog_posts, [ :series_id, :series_position ], unique: true
    if connection.adapter_name == "PostgreSQL"
      add_index :open_blog_posts, "to_tsvector('simple', search_text)", using: :gin, name: "index_open_blog_posts_search"
    end
    add_check_constraint :open_blog_posts, "body_format IN ('markdown', 'rich_text')", name: "open_blog_posts_body_format"
    add_check_constraint :open_blog_posts, "status IN ('draft', 'scheduled', 'published', 'archived')", name: "open_blog_posts_status"
    add_check_constraint :open_blog_posts, "provenance IN ('ai_assisted', 'human_written', 'unknown')", name: "open_blog_posts_provenance"
  end
end
