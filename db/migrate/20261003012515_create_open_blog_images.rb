class CreateOpenBlogImages < ActiveRecord::Migration[8.0]
  def change
    create_table :open_blog_images do |t|
      t.string :sha256, limit: 64, null: false
      t.string :filename, null: false
      t.string :content_type, null: false
      t.bigint :byte_size, null: false
      t.integer :width
      t.integer :height
      t.string :source_url
      t.string :uploaded_by
      t.datetime :created_at, null: false
    end
    add_index :open_blog_images, :sha256, unique: true
    add_check_constraint :open_blog_images, "byte_size >= 0", name: "open_blog_images_size"
  end
end
