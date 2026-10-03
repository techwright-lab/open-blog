# Open Blog

An agentic blog engine for Rails. **Not released:** the gem provides a mountable engine, content models, Ruby publishing operations, sanitized rendering, and reader pages for PostgreSQL and SQLite. Authenticated JSON publishing endpoints are available.

Install into a Rails 8 application with libvips available for image processing (or ImageMagick if your host uses that backend):

```sh
bundle add open_blog --github techwright-lab/open-blog
bin/rails generate open_blog:install --site-name="My Journal" --author-name="Example Author"
bin/dev
```

The generator installs the tables, mounts `/blog`, copies reader views and browser controllers, and publishes one sample article. It detects importmap or a JavaScript bundler and Tailwind 4. If Tailwind is absent, its installer also changes the host's application layout and development scripts. Use `--skip-tailwind` to keep the host's CSS setup and load the gem's compiled stylesheet only in the blog layout.

Options include `--mount-at=/journal`, `--mount-position=first`, `--body-format=markdown|rich_text|both`, `--skip-sample`, and `--skip-migrate`. The default mount position is last so existing host routes retain precedence. Repeating installation reuses the sample and migrations. `--skip-migrate` also defers the sample until you run the migrations. Changed files are kept in a noninteractive terminal; use `--force` to replace them. `bin/rails generate open_blog:views` refreshes only the copied views.

Run `bin/rails open_blog:doctor` to inspect configuration, assets, routes, storage, and publishing records. Errors return exit status 1; warnings identify setup still needed. Set your public origin and replace any placeholder identities in `config/initializers/open_blog.rb`:


```ruby
OpenBlog.configure do |config|
  config.site_name = "My Journal"
  config.public_base_url = "https://example.com"
  config.default_author = { name: "Example Author", type: :person }
  config.publisher = { name: "My Company", url: "https://example.com" }
end
```

Required configuration is checked at application boot. The copied templates live in the host's `app/views/open_blog` and call gem helpers for metadata, structured data, dates, and notices. Customize those views and `app/views/layouts/open_blog.html.erb` in your application.

Posts support Markdown or opt-in rich text, ordered FAQs, authors, categories, tags, and series. Revision identifiers are computed from normalized content; stored revisions, approvals, publication records, and images are immutable through the model APIs.

FAQ records appear as expanded plain text after the article and supply its FAQ structured data. Blank lines create paragraphs, single line breaks remain visible, and bare HTTP(S) URLs become links. Markdown and HTML-looking text in FAQ answers stay literal. `OpenBlog::MarkdownView.render(post)` returns a text version with truthful dates, notices, FAQs, and the canonical URL; its HTTP route is still under development.

Publish from Ruby with `OpenBlog::Publish.call({ title: "Garden notes", body: "Today in the garden." }, actor: "Editor")`. Every operation returns a result with `success?`, `post`, `records`, and a typed `error` on refusal. Updates to public content require `change: "substantive"`, `"correction"` (with `note`), or `"maintenance"`. Drafts use `OpenBlog::SaveDraft.call`.

Operation results include advisory findings and an AI notice label based on the current revision, approvals, and publisher configuration. These findings do not block publication. Direct FAQ and rich-text saves update content and revision records in the same transaction. Use normal model saves or the operations; bulk SQL writes such as `update_all` and `delete_all` bypass auditing.

The JSON API lives under `/blog/api/v1` (or your configured mount path). Create a token with `NAME="Publishing client" SCOPES=read,write,publish bin/rails open_blog:token` and keep the printed secret: only its digest is stored. Send it as `Authorization: Bearer ob_…`. `EXPIRES_AT` accepts an ISO 8601 timestamp; revoke a token by setting its `revoked_at`. A configured `config.authenticate` callback replaces token authentication and returns an actor with `name` and optional `scopes` and `id`.

| Request | Purpose | Scope |
| --- | --- | --- |
| `GET /posts`, `GET /posts/:id` | List or read posts, including drafts | `read` |
| `POST /posts` | Create or upsert by external ID or slug | `write` for drafts; `publish` with `publish: true` or when editing a scheduled/public post |
| `PATCH /posts/:id` | Edit while preserving the current publication state | `write` for drafts; `publish` for scheduled or public posts |
| `POST /posts/:id/publish`, `POST /posts/:id/unpublish` | Release or withdraw a post | `publish` |
| `DELETE /posts/:id` | Delete an unaudited draft or archive a post with history | `publish` |
| `POST /posts/:post_id/approvals`, `POST /posts/:post_id/connections` | Append an approval or connection declaration | `publish` |
| `GET /posts/:post_id/records`, `GET /posts/:post_id/findings`, `GET /doctor` | Inspect history, advisory findings, or installation checks | `read` |

IDs in these routes can also be slugs. Send JSON fields directly at the top level. For example, `POST /posts` with `{"title":"Winter garden","body":"Protect the young trees.","external_id":"garden-17"}` saves a draft. Publish it with `POST /posts/:id/publish` and an empty JSON object. Updating public content still requires the change classification described above. PATCH preserves omitted fields; supplied FAQ and tag arrays replace their lists. Unsupported fields return an error rather than being silently discarded.

The list endpoint accepts `status`, `category`, `tag`, `author`, `series`, `q`, `page`, and `per_page`; pagination defaults to 25 and permits at most 100 posts per page. It returns `{posts, page, per_page, total}` with compact post cards. Individual reads include content, media, revision identifiers, and notices. Writes return `{post, created, records, label, findings}`; record values are null when no corresponding audit record was made. New posts return 201, scheduled creation or publication returns 202, ordinary updates return 200, and deletion of a draft without retained history returns 204.

Errors return `{error: {code, message, details}}` with HTTP status 401 for missing authentication, 403 for insufficient scope, 404 for missing records, 409 for identity or revision conflicts, 422 for invalid input, and 429 for rate limits. API responses use `Cache-Control: no-store`. Requests share the configured rate limit per actor across endpoints; use a shared cache store when running multiple application processes.

API response fields are explicit:

| Object | Fields |
| --- | --- |
| Post card | `id`, `slug`, `url`, `status`, `title`, `description`, `author`, `category`, `tags`, `published_at`, `modified_at`, `revision_identifier`, `label` |
| Full post | Card fields plus `search_title`, `search_description`, `body_format`, `body`, `series`, `featured`, `canonical_url`, `cover_image`, `cover_alt`, `social_image`, `faq`, `provenance`, `provenance_evidence`, `external_id`, `publish_at`, `public_revision_identifier`, `approved`, `preview_url`, `reading_time_minutes`, `word_count`, `created_at`, `updated_at` |
| Author / category / series embedded in a post | Author: `{id, name, slug, type, url}`. Category: `{id, name, slug}` or null. Series: `{id, name, slug, position}` or null. Tags are names; FAQs contain `{question, answer}`. |
| Image | `image_id`, `url`, `sha256`, `filename`, `content_type`, `byte_size`, `width`, `height`; absent images are null |
| Write records | `revision` (new, same, or null), `publication` (entry type or null), `approval` (kind or null) |
| History | `{revisions, approvals, publications, baseline, connections}`; lists follow insertion order and an absent baseline is null |
| Revision | `identifier`, `actor`, `made_by_ai`, `created_at` |
| Approval | `kind`, `revision_identifier`, `reviewer_name`, `facts_checked`, `approved_at`, `declared_on`, `declared_by`, `confirmed_by`, `evidence`, `recorded_by` |
| Publication | `entry_type`, `revision_identifier`, `occurred_at`, `released_by`, `description`, `note` |
| Baseline | `post_id`, `adopted_at`, `adopted_revision_id`, `provenance`, `provenance_evidence`, `first_published_at`, `first_published_evidence`, `declared_first_published_at`, `last_modified_at`, `last_modified_evidence`, `source_system`, `source_id`, `source_body_sha256`, `adopted_by` |
| Connection declaration | `post_id`, `connections` (a list of `{party, relation}`), `third_party_paid`, `declared_by`, `declared_on`, `recorded_by` |
| Findings | `{findings: [...]}`; each item has `code`, `rule`, `message`, `location` |
| Doctor | `{checks: [...]}`; each item has `name`, `status` (ok, warning, or error), `message` |

`approved` describes a facts-checked approval for the public revision. Labels are `none`, `ai_assisted`, or `ai_unknown`. Preview URLs are currently null. Stored body and FAQ text are returned without changing their formatting. Connection writes append a complete declaration; send an empty connections array to declare none. Omitted declaration dates use the operation's date. Approval requests require `revision_identifier`, `name`, and boolean `facts_checked`.

These error codes are used by the current endpoints:

| HTTP status | Codes |
| --- | --- |
| 401 | `unauthenticated` |
| 403 | `scope_required` |
| 404 | `not_found` |
| 409 | `identity_conflict`, `slug_reserved`, `post_is_public`, `revision_mismatch` |
| 422 | `validation_failed`, `unknown_field`, `change_type_required`, `correction_note_required`, `approval_required`, `approval_incomplete`, `refused_by_host`, `body_format_not_permitted`, `image_not_permitted` |
| 429 | `rate_limited` |

`details` is always an array. It can identify rejected fields, a required scope, or messages supplied by the host publication hook. No token secret appears in API response objects.

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

With Tailwind 4, the copied theme lives in `app/assets/tailwind/open_blog` and the blog layout loads your host build. With `--skip-tailwind` or Tailwind 3, the layout loads the gem's compiled stylesheet followed by `app/assets/stylesheets/open_blog_theme.css`, where you can change fonts, colors, and spacing. The compiled stylesheet stays in the gem. Maintainers rebuild it with `bin/rails open_blog:build_css`; `OUT=/tmp/blog.css` selects another output path.

The installer copies browser controllers to `app/javascript/controllers/open_blog` and registers them with the `open-blog--` prefix. They enable the theme toggle, link and code copying, device sharing, table-of-contents tracking, and reading progress. If you change the blog layout to load a separate JavaScript entry point, register these controllers there too.

Licensed under the [MIT License](LICENSE.txt).
