---
layout: default
title: Page views
nav_order: 13
permalink: /analytics/
---

# Page views

Daily page views count successful HTML article GETs that reach Rails, including conditional 304 responses. The counter excludes common bots, missing User-Agent headers, prefetches, previews, Markdown, feeds, and redirects. It stores only article ID, UTC date, and count; it does not identify visitors or measure unique readers. Requests served entirely by a CDN or reverse-proxy cache are not counted. Counter errors are logged without interrupting the page.

Set `config.page_views = false` to disable counting, or replace `config.page_view_bot_pattern` with a regular expression for your traffic. `config.page_view_retention_days` defaults to `nil`; set a positive number and schedule `bin/rails open_blog:prune_page_views` to remove older rows. Enable the sidebar with `config.popular_posts = { enabled: true, days: 30, limit: 5 }`. Rankings cache for one hour, while withdrawn articles disappear immediately.

With a read-scoped API token, `GET /blog/api/v1/posts/:id/views?from=2026-01-01&to=2026-01-31` returns daily totals; omitted dates select the last 30 days. `GET /blog/api/v1/views/top?days=7&limit=3` ranks stored articles by views. MCP `blog_get_page_views` accepts either an article `id` with optional `from`/`to`, or optional `days`/`limit` for rankings. These authenticated reports can include articles that are no longer public; the public sidebar includes only currently listed articles.
