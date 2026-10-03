class CreateOpenBlogRevisions < ActiveRecord::Migration[8.0]
  def change
    create_table :open_blog_revisions do |t|
      t.references :post, null: false, foreign_key: { to_table: :open_blog_posts }
      t.string :identifier, limit: 64, null: false
      t.text :payload, null: false
      t.string :actor
      t.boolean :made_by_ai
      t.datetime :created_at, null: false
    end
    add_index :open_blog_revisions, [ :post_id, :identifier ], unique: true
    add_foreign_key :open_blog_posts, :open_blog_revisions, column: :public_revision_id
  end
end
