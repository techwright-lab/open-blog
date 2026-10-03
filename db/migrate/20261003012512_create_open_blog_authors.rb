class CreateOpenBlogAuthors < ActiveRecord::Migration[8.0]
  def change
    create_table :open_blog_authors do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :author_type, null: false, default: "person"
      t.text :bio
      t.string :url
      t.public_send(connection.adapter_name == "PostgreSQL" ? :jsonb : :json, :profile_urls, null: false, default: [])
      t.string :host_reference
      t.timestamps
    end
    add_index :open_blog_authors, :slug, unique: true
    add_check_constraint :open_blog_authors, "author_type IN ('person', 'organization')", name: "open_blog_authors_type"
  end
end
