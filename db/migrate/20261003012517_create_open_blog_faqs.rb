class CreateOpenBlogFaqs < ActiveRecord::Migration[8.0]
  def change
    create_table :open_blog_faqs do |t|
      t.references :post, null: false, foreign_key: { to_table: :open_blog_posts }
      t.integer :position, null: false
      t.text :question, null: false
      t.text :answer, null: false
      t.timestamps
    end
    add_index :open_blog_faqs, [ :post_id, :position ], unique: true
    add_check_constraint :open_blog_faqs, "position > 0", name: "open_blog_faqs_position"
  end
end
