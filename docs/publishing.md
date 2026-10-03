---
layout: default
title: Publishing
nav_order: 4
permalink: /publishing/
---

# Publishing

Posts support Markdown or opt-in rich text, ordered FAQs, authors, categories, tags, and series. Revision identifiers are computed from normalized content; stored revisions, approvals, publication records, and images are immutable through the model APIs.

## Ruby operations

Publish from Ruby with `OpenBlog::Publish.call({ title: "Garden notes", body: "Today in the garden." }, actor: "Editor")`. Every operation returns a result with `success?`, `post`, `records`, and a typed `error` on refusal. Updates to public content require `change: "substantive"`, `"correction"` (with `note`), or `"maintenance"`. Drafts use `OpenBlog::SaveDraft.call`.

Operation results include advisory findings and an AI notice label based on the current revision, approvals, and publisher configuration. These findings do not block publication. Direct FAQ and rich-text saves update content and revision records in the same transaction. Use normal model saves or the operations; bulk SQL writes such as `update_all` and `delete_all` bypass auditing.

## Previews

Preview links use Rails-signed tokens bound to the post's revision and `config.preview_expires_in` (default seven days). They open in the blog layout without sign-in, are not cached or indexed, and stop working after content changes or expiration. Changing the configured lifetime invalidates existing links. Publishing unchanged content makes an existing valid link redirect to the public article. Public edits have no separate draft preview in this version.

## Scheduling

Future `publish_at` values store a schedule and enqueue a job after commit. The job locks and reloads the article, publishes its latest content when due, and records the actual release time. Cancelled, moved, or already completed schedules are harmless to repeat. Scheduled execution does not require a new approval; content edited after review can therefore publish with a missing-approval notice. Host publication callbacks still apply. Use a durable Active Job adapter, or run `bin/rails open_blog:publish_due` regularly as a fallback.

## Agent review and provenance

Agent publishing instructions:

Show the final text to the user before publication and ask once whether they approve that exact version and have checked its facts. Include the preview link for unpublished content. Record approval only from an actual answer: send the user's name, facts_checked with their stated true or false value, and the reviewed draft's revision_identifier. For an approved public edit without a saved draft identifier, send the complete reviewed content and inline approval with the user's name and facts_checked answer, omitting approval.revision_identifier so the operation binds it to the new revision. Never attach the old public identifier to changed text. Compare the returned content with the reviewed version and report any unexpected difference. If no answer was given, omit approval. Never invent a review or a fact-check. When text changes after approval, show the new version and ask again.

Set provenance to ai_assisted if AI authored or rewrote any content, or human_written only when a person wrote all of it.

## Content images and findings

Publishing and draft operations resolve body images before recording revision identities. Image manifests survive reloads and child-record edits; metadata-only updates reuse them. Native rich-text saves can import existing uploaded blobs. External body image URLs remain unchanged. The gem downloads their bytes once when preparing changed content to record a digest; a refused or failed download leaves the image unverified and does not refuse the article. Metadata-only edits reuse the stored digest. Body findings report heading gaps, level-one headings, missing image descriptions, and external images. They also flag unavailable links within the blog mount using local routes and records, without making network requests. Links outside the mount are not checked by this finding.

For client requests and error responses, use the [JSON API reference]({% link api.md %}). The [adoption guide]({% link adoption.md %}) covers importing existing publications.
