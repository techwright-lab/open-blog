class AddOpenBlogApiTokenManagement < ActiveRecord::Migration[8.0]
  def change
    key_type = connection.columns(:open_blog_api_tokens).find { |column| column.name == "id" }.type

    change_table :open_blog_api_tokens do |t|
      t.string :creator_identity, index: true
      t.references :successor, type: key_type, index: { unique: true }, foreign_key: { to_table: :open_blog_api_tokens }
    end

    create_table :open_blog_api_token_events do |t|
      t.references :api_token, type: key_type, null: false, index: true, foreign_key: { to_table: :open_blog_api_tokens }
      t.string :actor_identity, null: false
      t.string :action, null: false
      t.public_send(connection.adapter_name == "PostgreSQL" ? :jsonb : :json, :details, null: false, default: {})
      t.datetime :created_at, null: false
    end
  end
end
