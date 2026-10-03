# Open Blog

An agentic blog engine for Rails. **Not released:** the gem provides a mountable engine, content models, Ruby publishing operations, sanitized rendering, and reader pages for PostgreSQL and SQLite. Installation tooling and publishing HTTP interfaces are under development.

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
Required configuration is checked at application boot. The reader templates are provided under `lib/generators/open_blog/install/templates/views`; copy them into the host's `app/views` until the install generator is available. The templates call gem helpers for metadata, structured data, dates, and notices.

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

Render stored content with `OpenBlog::Renderer.render(post)`, or preview a string with `OpenBlog::Renderer.render_string(text, format: :markdown)`. Both return sanitized HTML with heading links, syntax highlighting, image figures, and table wrappers. Markdown also supports task lists, footnotes, and alerts. Rich-text input cannot supply its own classes, IDs, styles, or event handlers. Rendering does not write records or fetch image bytes.

Publishing and draft operations resolve body images before recording revision identities. Image manifests survive reloads and child-record edits; metadata-only updates reuse them. Native rich-text saves can import existing uploaded blobs. External image URLs remain in the body; remote image fetching is still under development, so their bytes remain unverified. Body findings report heading gaps, level-one headings, missing image descriptions, and external images.

Generate syntax colors for the configured theme with `bin/rails open_blog:syntax_css`. The output includes light, explicit dark, and system dark rules scoped to code blocks. `config.syntax_theme` defaults to `"github"`; `"base16"` and `"gruvbox"` also support both modes.

Reader routes include the index, posts, categories, tags, authors, Atom feeds, and a sitemap. Lists paginate with `?page=2`; unavailable pages return 404. Post redirects return 301, and recorded removals return 410. `config.primary_list_type` selects categories or tags for indexing and sitemap inclusion. Reader dates use publication history rather than database update timestamps.

An adopted article with unknown historical dates omits those dates from the page and sitemap. Atom requires an update time, so it uses the adoption time until a substantive change or correction supplies a modification date. Maintenance does not advance that date.

Atom is available at `/blog/feed.xml` and `/blog/category/:slug/feed.xml`; set `config.feed_content = :full` for rendered bodies instead of summaries. `OpenBlog.sitemap_entries` returns absolute URL entries for integration with a host sitemap; set `config.serve_sitemap = false` to disable the engine's `/blog/sitemap.xml` endpoint. Custom mount paths apply to all reader routes.

Original images have stable URLs under `/blog/media/:sha256/:filename`. Redirect delivery caches only as long as the storage URL remains valid; `config.image_delivery = :proxy` serves immutable bytes with a one-year cache lifetime. Cards use Active Storage variants. Set `config.parent_controller` to inherit a host controller and its callbacks; the engine explicitly includes its helpers for custom parents.

Reader templates include responsive light and dark themes. `config.color_scheme` defaults to `:system`; readers can select light or dark, and their choice is saved locally in the browser. Set it to `:light` or `:dark` to fix the theme. Without JavaScript, pages remain readable and the system theme still applies.

The copied layout loads the gem's compiled stylesheet. Override its tokens in the host's `app/assets/stylesheets/open_blog_theme.css` to change fonts, colors, and spacing. Tailwind source templates are available under `lib/generators/open_blog/install/templates/theme`. Maintainers rebuild the bundled stylesheet with `bin/rails open_blog:build_css`.

The browser controllers live under `app/assets/javascripts/open_blog/controllers`. Register them with Stimulus using the `open-blog--` prefix to enable the theme toggle, link and code copying, device sharing, table-of-contents tracking, and reading progress. The install generator will wire them into the host's JavaScript setup; until then, the dummy application shows the importmap setup.

Licensed under the [MIT License](LICENSE.txt).
