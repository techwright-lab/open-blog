class CreateOpenBlogCategories < ActiveRecord::Migration[8.0]
  def change
    create_table :open_blog_categories do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :open_blog_categories, :name, unique: true
    add_index :open_blog_categories, :slug, unique: true
  end
end
