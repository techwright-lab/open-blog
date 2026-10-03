class CreateOpenBlogPublications < ActiveRecord::Migration[8.0]
  def change
    create_table :open_blog_publications do |t|
      t.references :post, null: false, foreign_key: { to_table: :open_blog_posts }
      t.references :revision, null: false, foreign_key: { to_table: :open_blog_revisions }
      t.string :entry_type, null: false
      t.datetime :occurred_at, null: false
      t.string :released_by
      t.string :description
      t.text :note
      t.datetime :created_at, null: false
    end
    add_index :open_blog_publications, [ :post_id, :occurred_at ]
    add_index :open_blog_publications, :post_id, unique: true, where: "entry_type = 'first'", name: "index_open_blog_publications_first"
    add_check_constraint :open_blog_publications, "entry_type IN ('first', 'substantive', 'correction', 'maintenance', 'adopted')", name: "open_blog_publications_entry_type"
    add_check_constraint :open_blog_publications, "entry_type != 'correction' OR note IS NOT NULL", name: "open_blog_publications_correction"
  end
end
