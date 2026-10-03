class CreateOpenBlogRedirects < ActiveRecord::Migration[8.0]
  def change
    create_table :open_blog_redirects do |t|
      t.string :old_path, null: false
      t.string :new_path
      t.string :source, null: false
      t.date :occurred_on, null: false
      t.references :post, foreign_key: { to_table: :open_blog_posts }
      t.timestamps
    end
    add_index :open_blog_redirects, :old_path, unique: true
    add_check_constraint :open_blog_redirects, "source IN ('slug_change', 'removal', 'unpublish', 'adoption', 'manual')", name: "open_blog_redirects_source"
  end
end
