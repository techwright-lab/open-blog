class CreateOpenBlogConnectionDeclarations < ActiveRecord::Migration[8.0]
  def change
    create_table :open_blog_connection_declarations do |t|
      t.references :post, null: false, foreign_key: { to_table: :open_blog_posts }
      t.public_send(connection.adapter_name == "PostgreSQL" ? :jsonb : :json, :connections, null: false, default: [])
      t.boolean :third_party_paid, null: false
      t.string :declared_by, null: false
      t.date :declared_on, null: false
      t.string :recorded_by
      t.datetime :created_at, null: false
    end
  end
end
