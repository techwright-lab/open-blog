# Open Blog

An agentic blog engine for Rails. **Not released:** the gem currently provides a mountable engine, configuration, content models, and Ruby publishing operations for PostgreSQL and SQLite. HTTP interfaces and reader pages are under development.

Configure the engine in `config/initializers/open_blog.rb`:

```ruby
OpenBlog.configure do |config|
  config.site_name = "My Journal"
  config.public_base_url = "https://example.com"
  config.default_author = { name: "Example Author", type: :person }
  config.publisher = { name: "My Company", url: "https://example.com" }
end
```

Mount it in `config/routes.rb` with `mount OpenBlog::Engine => "/blog"`.
Required configuration is checked at application boot. The mounted engine currently returns 404 until reader routes are added.

Posts support Markdown or opt-in rich text, ordered FAQs, authors, categories, tags, and series. Revision identifiers are computed from normalized content; stored revisions, approvals, publication records, and images are immutable through the model APIs.

Publish from Ruby with `OpenBlog::Publish.call({ title: "Garden notes", body: "Today in the garden." }, actor: "Editor")`. Every operation returns a result with `success?`, `post`, `records`, and a typed `error` on refusal. Updates to public content require `change: "substantive"`, `"correction"` (with `note`), or `"maintenance"`. Drafts use `OpenBlog::SaveDraft.call`.

Operation results include advisory findings and an AI notice label based on the current revision, approvals, and publisher configuration. These findings do not block publication. Direct FAQ and rich-text saves update content and revision records in the same transaction. Use normal model saves or the operations; bulk SQL writes such as `update_all` and `delete_all` bypass auditing.

Future `publish_at` values store a schedule and enqueue a job after commit. Scheduled job execution is still under development.

Import an existing published article with `OpenBlog::Adopt`. The source pair identifies the import, and adoption preserves its history without recording a new first publication:

```ruby
article = {
  source_system: "legacy-journal", source_id: "42",
  slug: "orchard-notes", title: "Orchard notes",
  body_format: "markdown", body: "Water young trees."
}

preview = OpenBlog::Adopt.call(article.merge(dry_run: true), actor: "Importer")
result = OpenBlog::Adopt.call(article, actor: "Importer")
```

Adoption accepts a full content snapshot: omitted FAQ and tag lists are cleared. Identical repeated imports leave records unchanged. Content or metadata can replace the initial adoption records until a later publication, removal, unpublish, or recorded URL move makes replacement unsafe. Connection declarations remain in history; an explicitly changed declaration appends a new record.

Historical dates require `first_published_evidence` or `last_modified_evidence`; without evidence they remain unknown. Use `imported_approval` for a confirmed approval record or `declaration` for a publisher's statement. A declaration can include `declared_first_published_at`. Ordinary `approval` is not an adoption input. Images accept an existing gem image ID or `{ signed_id: blob.signed_id }`, which reuses the stored blob. `dry_run: true` returns the proposed result without retaining database changes or uploading files.

`OpenBlog::FaqExtraction.call(body: markdown)` returns proposed FAQ pairs, byte ranges in `cut`, `body_after`, `leftover`, `reasons`, and a classification of `none`, `clean`, or `review`. Inspect the result before using it:

```ruby
extraction = OpenBlog::FaqExtraction.call(body: article[:body])
```

The extractor stores nothing and also returns `source_body_sha256` for recording the original body. Each cut range uses byte offsets with an exclusive end. Calls may provide `standalone_questions: ["How often should I water?"]` to identify specific level-two sections; these require review.

Licensed under the [MIT License](LICENSE.txt).
