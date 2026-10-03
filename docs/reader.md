---
layout: default
title: Reader pages and feeds
nav_order: 7
permalink: /reader/
---

# Reader pages and feeds

FAQ records appear as expanded plain text after the article and supply its FAQ structured data. Blank lines create paragraphs, single line breaks remain visible, and bare HTTP(S) URLs become links. Markdown and HTML-looking text in FAQ answers stay literal. `OpenBlog::MarkdownView.render(post)` returns a text version with truthful dates, notices, FAQs, and the canonical URL; the same text is available at `/blog/:slug.md`, with canonical and noindex headers.

Readers can browse an ordered series at `/blog/series/:slug`; member articles link to the previous and next published article. Search at `/blog/search?q=words` covers titles, article text, and FAQ records. Queries must contain 2–100 characters. PostgreSQL uses ranked full-text search; SQLite matches every word. The sidebar offers live suggestions from `/blog/search.json` and also works as an ordinary search form without JavaScript. Search shares `config.search_rate_limit` across HTML and JSON requests per address (default 30 per minute).

Atom and JSON Feed 1.1 are available at `/blog/feed.xml` and `/blog/feed.json`, with category feeds under `/blog/category/:slug/feed.xml` and `.json`. Both use `config.feed_size` and `config.feed_content` (`:summary` or `:full`), and cache publicly for one hour. JSON summary entries include plain-text content. Unknown historical publication dates are omitted. Atom requires an `updated` value: when an adopted article has no known publication or modification date, the feed uses the recorded adoption time. This fallback describes the available record, not a claimed original publication date.

## Routes and dates

Reader routes include the index, posts, categories, tags, authors, Atom feeds, and a sitemap. Lists paginate with `?page=2`; unavailable pages return 404. Post redirects return 301, and recorded removals return 410. `config.primary_list_type` selects categories or tags for indexing and sitemap inclusion. Reader dates use publication history rather than database update timestamps.

An adopted article with unknown historical dates omits those dates from the page and sitemap. Atom requires an update time, so it uses the adoption time until a substantive change or correction supplies a modification date. Maintenance does not advance that date.

Atom is available at `/blog/feed.xml` and `/blog/category/:slug/feed.xml`; set `config.feed_content = :full` for rendered bodies instead of summaries. `OpenBlog.sitemap_entries` returns absolute URL entries for integration with a host sitemap; set `config.serve_sitemap = false` to disable the engine's `/blog/sitemap.xml` endpoint. Custom mount paths apply to all reader routes.

## Image delivery

Original images have stable URLs under `/blog/media/:sha256/:filename`. Redirect delivery caches only as long as the storage URL remains valid; `config.image_delivery = :proxy` serves immutable bytes with a one-year cache lifetime. Cards use Active Storage variants. Set `config.parent_controller` to inherit a host controller and its callbacks; the engine explicitly includes its helpers for custom parents.

## Policy pages

Policy pages use four fixed kinds: `responsible_party`, `corrections`, `editorial`, and `ai_use`. Save `title`, Markdown `body`, and `status` (`draft` or `published`) with `PUT /pages/:kind`. Optional fields are `slug`, `approved_by`, and an ISO date `approved_on`. A supplied nonblank approver defaults the omitted date to today; approval names are never filled automatically. Omitted fields retain their values. No policy text is supplied by the gem.

Published pages appear at `/blog/policies/:slug`, in the footer, and in the sitemap. Drafts return 404 publicly. `config.policy_urls[:kind]` can point to an existing host page; this overrides the local link and hides that kind's gem-hosted page. `OpenBlog.policy_url(kind)` resolves the configured URL or published local path. Publishing or withdrawing the responsible-party page immediately updates relevant post notices without changing the posts' revision records or dates. Doctor checks configured URLs and recognizes published local pages.
