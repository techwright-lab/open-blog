class CreateOpenBlogApprovals < ActiveRecord::Migration[8.0]
  def change
    create_table :open_blog_approvals do |t|
      t.references :post, null: false, foreign_key: { to_table: :open_blog_posts }
      t.references :revision, null: false, foreign_key: { to_table: :open_blog_revisions }
      t.string :kind, null: false
      t.string :reviewer_name, null: false
      t.boolean :facts_checked, null: false
      t.datetime :approved_at, null: false
      t.date :declared_on
      t.string :declared_by
      t.string :confirmed_by
      t.text :evidence
      t.string :recorded_by
      t.datetime :created_at, null: false
    end
    add_check_constraint :open_blog_approvals, "kind IN ('sent', 'imported', 'declared')", name: "open_blog_approvals_kind"
    add_check_constraint :open_blog_approvals, "kind != 'declared' OR (declared_on IS NOT NULL AND declared_by IS NOT NULL)", name: "open_blog_approvals_declaration"
    add_check_constraint :open_blog_approvals, "kind != 'imported' OR (confirmed_by IS NOT NULL AND evidence IS NOT NULL)", name: "open_blog_approvals_import"
  end
end
