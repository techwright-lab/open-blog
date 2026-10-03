class CreateOpenBlogPageViews < ActiveRecord::Migration[8.0]
  def change
    create_table :open_blog_page_views do |t|
      t.references :post, null: false, foreign_key: { to_table: :open_blog_posts }, index: false
      t.date :day, null: false
      t.integer :views, null: false, default: 0
    end
    add_index :open_blog_page_views, [ :post_id, :day ], unique: true
    add_index :open_blog_page_views, :day
  end
end
