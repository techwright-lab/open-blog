---
layout: default
title: Publishing
nav_order: 4
permalink: /publishing/
---

# Publishing

Posts support Markdown or opt-in rich text, ordered FAQs, authors, categories, tags, and series. Revision identifiers are computed from normalized content; stored revisions, approvals, publication records, and images are immutable through the model APIs.

## Ruby operations

Every operation returns an `OpenBlog::Result` with `success?`, `post`, `created`, `records`, `label`, `findings`, and a typed `error` on refusal.

```ruby
result = OpenBlog::Publish.call(
  { title: "Garden notes", body: "Today in the garden.", provenance: "human_written" },
  actor: "Editor"
)

result.success?     # => true
result.post.path    # => "/blog/garden-notes"
result.records      # => { revision: "new", publication: "first", approval: nil }
result.label        # => :none
result.findings.map { |finding| finding[:code] }
# => [:description_absent, :category_absent, :author_default_used,
#     :connections_not_declared, :responsible_party_absent, :social_image_absent]
```

Updates to public content require `change: "substantive"`, `"correction"` (with `note`), or `"maintenance"`. Without it the operation refuses and nothing is written:

```ruby
update = OpenBlog::Publish.call({ body: "The beans came up." }, post: result.post, actor: "Editor")
update.success?     # => false
update.error.code   # => :change_type_required

update = OpenBlog::Publish.call({ body: "The beans came up.", change: "substantive" }, post: result.post, actor: "Editor")
update.records      # => { revision: "new", publication: "substantive", approval: nil }
```

The other operations take the same `actor:` keyword:

| Operation | Call | Effect |
| --- | --- | --- |
| `OpenBlog::SaveDraft` | `.call(attributes, post: nil, actor:)` | Save without publishing. Upserts by `external_id` or `slug`. |
| `OpenBlog::Approve` | `.call(post, revision_identifier:, name:, facts_checked:, actor:)` | Record a review of the public revision. Refuses with `revision_mismatch` when the identifier differs. |
| `OpenBlog::Unpublish` | `.call(post, actor:)` | Return a post to draft. A public path gets a removal record and answers 410. |
| `OpenBlog::Remove` | `.call(post, redirect_to: nil, actor:)` | Delete an unaudited draft, or archive a post with history and record a redirect or removal. |
| `OpenBlog::Adopt` | `.call(attributes, actor:)` | Import an existing article. See [adoption]({% link adoption.md %}). |

Operation results include advisory findings and an AI notice label based on the current revision, approvals, and publisher configuration. These findings do not block publication. Direct FAQ and rich-text saves update content and revision records in the same transaction. Use normal model saves or the operations; bulk SQL writes such as `update_all` and `delete_all` bypass auditing.

## Previews

Preview links use Rails-signed tokens bound to the post's revision and `config.preview_expires_in` (default seven days). They open in the blog layout without sign-in, are not cached or indexed, and stop working after content changes or expiration. Changing the configured lifetime invalidates existing links. Publishing unchanged content makes an existing valid link redirect to the public article. Public edits have no separate draft preview in this version.

## Scheduling

Future `publish_at` values store a schedule and enqueue a job after commit. The job locks and reloads the article, publishes its latest content when due, and records the actual release time. Cancelled, moved, or already completed schedules are harmless to repeat. Scheduled execution does not require a new approval; content edited after review can therefore publish with a missing-approval notice. Host publication callbacks still apply. Use a durable Active Job adapter, or run `bin/rails open_blog:publish_due` regularly as a fallback.

```ruby
OpenBlog::Publish.call({ title: "Spring plan", body: "Sow in March.", publish_at: 2.days.from_now }, actor: "Editor")
```

## Approval and provenance

An approval records that a named person reviewed one exact revision and whether they checked its facts. The AI notice label clears only when the public revision has a facts-checked approval, the responsible-party policy page exists, and every image has a digest. `config.require_approval` turns the approval into a hard gate for posts that are not `human_written`; `config.before_publish` lets the host refuse with its own messages. See [configuration]({% link configuration.md %}#content-and-publishing).

Agents must follow the [publishing instructions]({% link mcp.md %}#publishing-instructions): show the exact text, ask once, and never invent an approval.

## Content images and findings

Publishing and draft operations resolve body images before recording revision identities. Image manifests survive reloads and child-record edits; metadata-only updates reuse them. Native rich-text saves can import existing uploaded blobs. External body image URLs remain unchanged. The gem downloads their bytes once when preparing changed content to record a digest; a refused or failed download leaves the image unverified and does not refuse the article. Metadata-only edits reuse the stored digest. Body findings report heading gaps, level-one headings, missing image descriptions, and external images. They also flag unavailable links within the blog mount using local routes and records, without making network requests. Links outside the mount are not checked by this finding.

For client requests and error responses, use the [JSON API reference]({% link api.md %}). The [adoption guide]({% link adoption.md %}) covers importing existing publications.
