---
layout: default
title: JSON API
nav_order: 5
permalink: /api/
---

# JSON API

All request paths in the tables below are relative to `/blog/api/v1`, or the corresponding path below your configured mount.

## Authentication

Create a token with `NAME="Publishing client" SCOPES=read,write,publish bin/rails open_blog:token` and keep the printed secret: only its digest is stored. Send it as `Authorization: Bearer ob_…`. `EXPIRES_AT` accepts an ISO 8601 timestamp; revoke a token by setting its `revoked_at`. A configured `config.authenticate` callback replaces token authentication and returns an actor with `name` and optional `scopes` and `id`.

Requests without a valid token return 401:

```sh
curl -s https://example.com/blog/api/v1/posts
```

```json
{"error":{"code":"unauthenticated","message":"An authenticated actor is required.","details":[]}}
```

## First post

Save a draft, publish it, then try an edit without a change type. Set `TOKEN` to the printed secret.

```sh
curl -s -X POST https://example.com/blog/api/v1/posts \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"title":"Winter garden","body":"Protect the young trees.","external_id":"garden-17"}'
```

The response is 201 with the full post and the write envelope. Nothing is recorded for a draft, so every record value is null:

```json
{
  "post": {
    "id": 228,
    "slug": "winter-garden",
    "url": "https://example.com/blog/winter-garden",
    "status": "draft",
    "title": "Winter garden",
    "body_format": "markdown",
    "body": "Protect the young trees.",
    "revision_identifier": "95fde1cf890a2a8f994cbfa19ddbaa10caf5e03a5f61585ad0ce288dfea59404",
    "public_revision_identifier": null,
    "preview_url": "https://example.com/blog/preview/eyJfcmFpbHMi…",
    "label": "ai_unknown",
    "...": "see Response objects"
  },
  "created": true,
  "records": {"revision": null, "publication": null, "approval": null},
  "label": "ai_unknown",
  "findings": [
    {
      "code": "description_absent",
      "rule": "T8",
      "message": "Add a description for readers and search results.",
      "location": "description"
    },
    {
      "code": "provenance_unknown",
      "rule": "E18",
      "message": "Specify whether AI contributed to this post.",
      "location": "provenance"
    }
  ]
}
```

```sh
curl -s -X POST https://example.com/blog/api/v1/posts/228/publish \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{}'
```

```json
{
  "post": {"id": 228, "slug": "winter-garden", "status": "published", "public_revision_identifier": "95fde1cf…", "...": "..."},
  "created": false,
  "records": {"revision": "new", "publication": "first", "approval": null},
  "label": "ai_unknown",
  "findings": ["..."]
}
```

A public post keeps its history. An edit that changes the public revision must say what kind of change it is, or it is refused with 422 and nothing is written:

```sh
curl -s -X PATCH https://example.com/blog/api/v1/posts/228 \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"body":"Protect the young trees with fleece."}'
```

```json
{"error":{"code":"change_type_required","message":"This update changes the public revision. Send change: substantive, correction or maintenance.","details":[]}}
```

Add `"change":"substantive"` to the same request and it returns 200 with `"publication": "substantive"`. Read the history afterwards:

```sh
curl -s https://example.com/blog/api/v1/posts/228/records -H "Authorization: Bearer $TOKEN"
```

```json
{
  "revisions": [{"identifier": "95fde1cf…", "actor": "Publishing client", "made_by_ai": null, "created_at": "2026-10-03T20:59:05.711Z"}],
  "approvals": [],
  "publications": [{"entry_type": "first", "occurred_at": "2026-10-03T20:59:05.711Z", "released_by": "Publishing client", "description": null, "note": null, "revision_identifier": "95fde1cf…"}],
  "baseline": null,
  "connections": []
}
```

## Endpoints

| Request | Purpose | Scope |
| --- | --- | --- |
| `GET /posts`, `GET /posts/:id` | List or read posts, including drafts | `read` |
| `POST /posts` | Create or upsert by external ID or slug | `write` for drafts; `publish` with `publish: true` or when editing a scheduled/public post |
| `PATCH /posts/:id` | Edit while preserving the current publication state | `write` for drafts; `publish` for scheduled or public posts |
| `POST /posts/:id/publish`, `POST /posts/:id/unpublish` | Release or withdraw a post | `publish` |
| `DELETE /posts/:id` | Delete an unaudited draft or archive a post with history | `publish` |
| `POST /posts/:post_id/approvals`, `POST /posts/:post_id/connections` | Append an approval or connection declaration | `publish` |
| `GET /posts/:post_id/records`, `GET /posts/:post_id/findings`, `GET /doctor` | Inspect history, advisory findings, or installation checks | `read` |
| `GET /posts/:post_id/preview` | Get an unpublished post’s preview link and revision identifier | `read` |
| `POST /images` | Upload an image or import one from a URL | `write` |
| `GET /categories`, `GET /tags`, `GET /authors`, `GET /series`, `GET /redirects` | List supporting records | `read` |
| `POST /categories`, `POST /authors`, `POST /series`; `PATCH` their `/:id` routes | Create or edit supporting records | `write` |
| `POST /redirects`, `DELETE /redirects/:id` | Add a URL move or removal, or remove its record | `publish` |
| `POST /adoptions` | Import one existing article, with optional dry run | `publish` |
| `POST /faq_extractions` | Propose FAQ pairs and source ranges without saving | `read` |
| `GET /pages`, `GET /pages/:kind` | List or read policy pages, including drafts | `read` |
| `PUT /pages/:kind` | Create or edit a policy page | `write`; also `publish` when publishing or changing a published page |
| `GET /report` | Fetch a [surface report]({% link diagnostics.md %}#surface-reports) | `read` |
| `GET /posts/:id/views`, `GET /views/top` | [Page-view reports]({% link analytics.md %}) | `read` |

Post IDs in these routes can also be slugs. Send JSON fields directly at the top level. Publish a draft with `POST /posts/:id/publish` and an empty JSON object, or create and publish in one request with `"publish": true`. Updating public content requires the [change classification]({% link publishing.md %}#ruby-operations). PATCH preserves omitted fields; supplied FAQ and tag arrays replace their lists. Unsupported fields return an error rather than being silently discarded.

The list endpoint accepts `status`, `category`, `tag`, `author`, `series`, `q`, `page`, and `per_page`; pagination defaults to 25 and permits at most 100 posts per page.

```sh
curl -s "https://example.com/blog/api/v1/posts?status=published&per_page=2" -H "Authorization: Bearer $TOKEN"
```

```json
{
  "posts": [
    {"id": 228, "slug": "winter-garden", "url": "https://example.com/blog/winter-garden", "status": "published", "title": "Winter garden",
     "description": "", "author": {"id": 405, "name": "Ada Example", "slug": "ada-example", "type": "person", "url": null},
     "category": null, "tags": [], "published_at": "2026-10-03T20:59:05Z", "modified_at": "2026-10-03T20:59:05Z",
     "revision_identifier": "95fde1cf…", "label": "ai_unknown"},
    {"id": 226, "slug": "garden-notes", "...": "..."}
  ],
  "page": 1,
  "per_page": 2,
  "total": 2
}
```

Individual reads include content, media, revision identifiers, and notices. Writes return `{post, created, records, label, findings}`; record values are null when no corresponding audit record was made. New posts return 201, scheduled creation or publication returns 202, ordinary updates return 200, and deletion of a draft without retained history returns 204.

Errors return `{error: {code, message, details}}` with HTTP status 401 for missing authentication, 403 for insufficient scope, 404 for missing records, 409 for identity or revision conflicts, 422 for invalid input, and 429 for rate limits. API responses use `Cache-Control: no-store`. Requests share `config.api_rate_limit` per actor across endpoints; use a shared cache store when running multiple application processes.

## Response objects

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
| Preview | `preview_url`, `revision_identifier`, `expires_at` |
| Page | `kind`, `slug`, `url`, `title`, `body`, `status`, `approved_by`, `approved_on`, `updated_at` |
| Findings | `{findings: [...]}`; each item has `code`, `rule`, `message`, `location` |
| Doctor | `{checks: [...]}`; each item has `name`, `status` (ok, warning, or error), `message` |
| Category | `id`, `name`, `slug`, `description`, `position`, `posts_count` |
| Tag | `id`, `name`, `slug`, `posts_count` |
| Author | `id`, `name`, `slug`, `type`, `bio`, `url`, `profile_urls`, `avatar` (image or null), `host_reference`, `posts_count` |
| Series | `id`, `name`, `slug`, `description`, `posts` (items with `id`, `slug`, `title`, `position`) |
| Redirect | `id`, `old_path`, `new_path`, `source`, `occurred_on`, `post_id` |
| Adoption | `post`, `created`, `records` (`revision`, `publication`, `approval`, `baseline`, `redirects`), `findings`, `dry_run` |
| FAQ extraction | `pairs`, `cut`, `body_after`, `leftover`, `class`, `reasons`, `source_body_sha256` |

`approved` describes a facts-checked approval for the public revision. Labels are `none`, `ai_assisted`, or `ai_unknown`. Drafts and scheduled posts include a preview URL; public and archived posts return null. Stored body and FAQ text are returned without changing their formatting. Connection writes append a complete declaration; send an empty connections array to declare none. Omitted declaration dates use the operation's date. Approval requests require `revision_identifier`, `name`, and boolean `facts_checked`:

```sh
curl -s -X POST https://example.com/blog/api/v1/posts/228/approvals \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"revision_identifier":"95fde1cf890a2a8f994cbfa19ddbaa10caf5e03a5f61585ad0ce288dfea59404","name":"Casey","facts_checked":true}'
```

## Errors

These error codes are used by the current endpoints:

| HTTP status | Codes |
| --- | --- |
| 401 | `unauthenticated` |
| 403 | `scope_required` |
| 404 | `not_found` |
| 409 | `identity_conflict`, `slug_reserved`, `post_is_public`, `revision_mismatch`, `already_changed_in_gem` |
| 422 | `validation_failed`, `unknown_field`, `change_type_required`, `correction_note_required`, `approval_required`, `approval_incomplete`, `refused_by_host`, `body_format_not_permitted`, `slug_not_supported`, `image_not_permitted` |
| 429 | `rate_limited` |

`details` is always an array. It can identify rejected fields, a required scope, or messages supplied by the host publication hook. No token secret appears in API response objects.

## Images

Upload images as multipart `file` data, or send `{"url":"https://images.example.com/photo.png"}` to `/images`. Repeated bytes reuse the same image and URL. Cover, social image, and author avatar inputs accept `{image_id: ...}`, `{signed_id: ...}`, or `{url: ...}`. URL imports verify the file bytes, enforce the configured size limit and a ten-second deadline, allow at most three redirects, and refuse private or other nonpublic addresses at every hop. SVG is refused. `config.image_fetch_policy = :open` permits internal image servers while retaining the other limits; Doctor reports this setting.

```sh
curl -s -X POST https://example.com/blog/api/v1/images \
  -H "Authorization: Bearer $TOKEN" -F "file=@cover.png"
```

## Supporting records and imports

Supporting record lists use the same pagination envelope, with the corresponding plural key. Counts include stored posts, including drafts. Category writes accept `name`, `slug`, `description`, and `position`; series writes accept `name`, `slug`, and `description`; author writes accept the author fields above except `id` and `posts_count`. An avatar attached directly by the host appears as null until its blob is imported as a gem image. Redirect writes accept `old_path`, `new_path` (null for removal), optional `post_id`, and optional `occurred_on` (defaults to today); API-created redirects have source `manual`.

`POST /adoptions` accepts the same snapshot fields as the [Ruby adoption operation]({% link adoption.md %}). `dry_run: true` returns the proposed content and records without retaining rows or uploaded files. `POST /faq_extractions` accepts `body` and optional `standalone_questions`; it returns proposed text changes without applying them.

## Policy pages

`PUT /pages/:kind` saves one of the four policy pages. See [reader pages]({% link reader.md %}#policy-pages) for the kinds, the fields, and how published pages appear to readers.

```sh
curl -s -X PUT https://example.com/blog/api/v1/pages/responsible_party \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"title":"Who runs this blog","body":"My Company, Example Street 1.","status":"published","approved_by":"Casey"}'
```
