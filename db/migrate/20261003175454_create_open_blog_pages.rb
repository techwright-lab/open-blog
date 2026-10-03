class CreateOpenBlogPages < ActiveRecord::Migration[8.0]
  def change
    create_table :open_blog_pages do |t|
      t.string :kind, null: false
      t.string :slug, null: false
      t.string :title, null: false
      t.text :body_markdown, null: false, default: ""
      t.string :status, null: false, default: "draft"
      t.string :approved_by
      t.date :approved_on
      t.datetime :updated_at, null: false
    end
    add_index :open_blog_pages, :kind, unique: true
    add_index :open_blog_pages, :slug, unique: true
  end
end
