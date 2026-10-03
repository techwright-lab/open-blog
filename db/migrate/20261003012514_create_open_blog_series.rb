class CreateOpenBlogSeries < ActiveRecord::Migration[8.0]
  def change
    create_table :open_blog_series do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.timestamps
    end
    add_index :open_blog_series, :slug, unique: true
  end
end
