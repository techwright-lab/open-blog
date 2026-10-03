class AddBodyImageManifestToOpenBlogPosts < ActiveRecord::Migration[8.0]
  def change
    format = connection.adapter_name == "PostgreSQL" ? :jsonb : :json
    add_column :open_blog_posts, :body_image_manifest, format, null: false, default: []
    add_column :open_blog_posts, :body_image_source_digest, :string, limit: 64
  end
end
