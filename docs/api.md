---
layout: default
title: JSON API
nav_order: 5
permalink: /api/
---

# JSON API

All request paths in the tables below are relative to `/blog/api/v1`, or the corresponding path below your configured mount.

## Authentication

The JSON API lives under `/blog/api/v1` (or your configured mount path). Create a token with `NAME="Publishing client" SCOPES=read,write,publish bin/rails open_blog:token` and keep the printed secret: only its digest is stored. Send it as `Authorization: Bearer ob_…`. `EXPIRES_AT` accepts an ISO 8601 timestamp; revoke a token by setting its `revoked_at`. A configured `config.authenticate` callback replaces token authentication and returns an actor with `name` and optional `scopes` and `id`.

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

Post IDs in these routes can also be slugs. Send JSON fields directly at the top level. For example, `POST /posts` with `{"title":"Winter garden","body":"Protect the young trees.","external_id":"garden-17"}` saves a draft. Publish it with `POST /posts/:id/publish` and an empty JSON object. Updating public content requires the [change classification]({% link publishing.md %}#ruby-operations). PATCH preserves omitted fields; supplied FAQ and tag arrays replace their lists. Unsupported fields return an error rather than being silently discarded.

The list endpoint accepts `status`, `category`, `tag`, `author`, `series`, `q`, `page`, and `per_page`; pagination defaults to 25 and permits at most 100 posts per page. It returns `{posts, page, per_page, total}` with compact post cards. Individual reads include content, media, revision identifiers, and notices. Writes return `{post, created, records, label, findings}`; record values are null when no corresponding audit record was made. New posts return 201, scheduled creation or publication returns 202, ordinary updates return 200, and deletion of a draft without retained history returns 204.

Errors return `{error: {code, message, details}}` with HTTP status 401 for missing authentication, 403 for insufficient scope, 404 for missing records, 409 for identity or revision conflicts, 422 for invalid input, and 429 for rate limits. API responses use `Cache-Control: no-store`. Requests share the configured rate limit per actor across endpoints; use a shared cache store when running multiple application processes.

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

`approved` describes a facts-checked approval for the public revision. Labels are `none`, `ai_assisted`, or `ai_unknown`. Drafts and scheduled posts include a preview URL; public and archived posts return null. Stored body and FAQ text are returned without changing their formatting. Connection writes append a complete declaration; send an empty connections array to declare none. Omitted declaration dates use the operation's date. Approval requests require `revision_identifier`, `name`, and boolean `facts_checked`.

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

## Supporting records and imports

Supporting record lists use the same pagination envelope, with the corresponding plural key. Counts include stored posts, including drafts. Category writes accept `name`, `slug`, `description`, and `position`; series writes accept `name`, `slug`, and `description`; author writes accept the author fields above except `id` and `posts_count`. An avatar attached directly by the host appears as null until its blob is imported as a gem image. Redirect writes accept `old_path`, `new_path` (null for removal), optional `post_id`, and optional `occurred_on` (defaults to today); API-created redirects have source `manual`.

`POST /adoptions` accepts the same snapshot fields as the [Ruby adoption operation]({% link adoption.md %}). `dry_run: true` returns the proposed content and records without retaining rows or uploaded files. `POST /faq_extractions` accepts `body` and optional `standalone_questions`; it returns proposed text changes without applying them.

## Policy pages

Policy pages use four fixed kinds: `responsible_party`, `corrections`, `editorial`, and `ai_use`. Save `title`, Markdown `body`, and `status` (`draft` or `published`) with `PUT /pages/:kind`. Optional fields are `slug`, `approved_by`, and an ISO date `approved_on`. A supplied nonblank approver defaults the omitted date to today; approval names are never filled automatically. Omitted fields retain their values. No policy text is supplied by the gem.

Published pages appear at `/blog/policies/:slug`, in the footer, and in the sitemap. Drafts return 404 publicly. `config.policy_urls[:kind]` can point to an existing host page; this overrides the local link and hides that kind's gem-hosted page. `OpenBlog.policy_url(kind)` resolves the configured URL or published local path. Publishing or withdrawing the responsible-party page immediately updates relevant post notices without changing the posts' revision records or dates. Doctor checks configured URLs and recognizes published local pages.

## Reports and analytics

The read-scoped `GET /report` endpoint returns a [surface report]({% link diagnostics.md %}#surface-reports). `GET /posts/:id/views` and `GET /views/top` provide [page-view reports]({% link analytics.md %}).
