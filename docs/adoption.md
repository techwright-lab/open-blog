---
layout: default
title: Adopting existing articles
nav_order: 9
permalink: /adoption/
---

# Adopting existing articles

Import an existing published article with `OpenBlog::Adopt`. The source pair identifies the import, and adoption preserves its history without recording a new first publication:

```ruby
article = {
  source_system: "legacy-journal", source_id: "42",
  slug: "orchard-notes", title: "Orchard notes",
  body_format: "markdown", body: "Water young trees."
}

preview = OpenBlog::Adopt.call(article.merge(dry_run: true), actor: "Importer")
result = OpenBlog::Adopt.call(article, actor: "Importer")
result.records   # => { revision: "new", publication: "adopted", approval: nil, baseline: "new", redirects: 0 }
```

Adoption accepts a full content snapshot: omitted FAQ and tag lists are cleared. Identical repeated imports leave records unchanged. Content or metadata can replace the initial adoption records until a later publication, removal, unpublish, or recorded URL move makes replacement unsafe. Connection declarations remain in history; an explicitly changed declaration appends a new record.

Historical dates require `first_published_evidence` or `last_modified_evidence`; without evidence they remain unknown. Use `imported_approval` for a confirmed approval record or `declaration` for a publisher's statement. A declaration can include `declared_first_published_at`. Ordinary `approval` is not an adoption input. Images accept an existing gem image ID or `{ signed_id: blob.signed_id }`, which reuses the stored blob. `dry_run: true` returns the proposed result without retaining database changes or uploading files.

```ruby
OpenBlog::Adopt.call(article.merge(
  first_published_at: "2024-03-01T09:00:00Z",
  first_published_evidence: "Legacy CMS export, row 42",
  declaration: { reviewer_name: "Casey", approved_at: "2024-03-01T08:30:00Z", facts_checked: true,
                 declared_on: "2026-10-03", declared_by: "Ravi" }
), actor: "Importer")
```

The same snapshot is accepted by `POST /adoptions` in the [JSON API]({% link api.md %}#supporting-records-and-imports) and by the `blog_adopt_post` MCP tool.

## Historical evidence

Give these instructions to any agent that adopts existing articles. The packaged adopt workflow carries the same text:

> Ask whether the original system has an approval record for the imported article. Use imported_approval only with its reviewer, original time, evidence, and the person confirming that it covers this content. Otherwise, record a declaration only when the user supplies the reviewer, approval time, facts_checked answer, declaration date, and their own name. Ask for a declared first publication date when historical evidence is missing, and place that answer in declaration.declared_first_published_at. Do not send approval in an adoption request or invent historical evidence or declarations.

## FAQ extraction

`OpenBlog::FaqExtraction.call(body: markdown)` returns proposed FAQ pairs, byte ranges in `cut`, `body_after`, `leftover`, `reasons`, and a classification of `none`, `clean`, or `review`. Inspect the result before using it:

```ruby
extraction = OpenBlog::FaqExtraction.call(body: article[:body])
extraction[:class]   # => "none", "clean", or "review"
extraction[:pairs]   # => [{ question: "...", answer: "..." }, ...]
```

The extractor stores nothing and also returns `source_body_sha256` for recording the original body. Each cut range uses byte offsets with an exclusive end. Calls may provide `standalone_questions: ["How often should I water?"]` to identify specific level-two sections; these require review.

See [reader dates and feeds]({% link reader.md %}#feeds-and-dates) for how unknown historical dates appear to readers.
