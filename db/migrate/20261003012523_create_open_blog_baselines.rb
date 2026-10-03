class CreateOpenBlogBaselines < ActiveRecord::Migration[8.0]
  def change
    create_table :open_blog_baselines do |t|
      t.references :post, null: false, index: { unique: true }, foreign_key: { to_table: :open_blog_posts }
      t.datetime :adopted_at, null: false
      t.references :adopted_revision, null: false, foreign_key: { to_table: :open_blog_revisions }
      t.string :provenance, null: false
      t.text :provenance_evidence
      t.datetime :first_published_at
      t.text :first_published_evidence
      t.datetime :declared_first_published_at
      t.datetime :last_modified_at
      t.text :last_modified_evidence
      t.string :source_system
      t.string :source_id
      t.string :source_body_sha256, limit: 64
      t.string :adopted_by
      t.datetime :created_at, null: false
    end
    add_index :open_blog_baselines, [ :source_system, :source_id ], unique: true
    add_check_constraint :open_blog_baselines, "first_published_at IS NULL OR declared_first_published_at IS NULL", name: "open_blog_baselines_first_date"
    add_check_constraint :open_blog_baselines, "provenance IN ('ai_assisted', 'human_written', 'unknown')", name: "open_blog_baselines_provenance"
  end
end
