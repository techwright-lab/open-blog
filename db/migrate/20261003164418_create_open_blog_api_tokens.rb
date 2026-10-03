class CreateOpenBlogApiTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :open_blog_api_tokens do |t|
      t.string :name, null: false
      t.string :token_digest, limit: 64, null: false
      t.string :token_prefix, limit: 8, null: false
      t.public_send(connection.adapter_name == "PostgreSQL" ? :jsonb : :json, :scopes, null: false, default: %w[read write publish])
      t.datetime :last_used_at
      t.datetime :expires_at
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :open_blog_api_tokens, :token_digest, unique: true
  end
end
