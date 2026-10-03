---
layout: default
title: Reader pages and feeds
nav_order: 7
permalink: /reader/
---

# Reader pages and feeds

Reader routes include the index, posts, categories, tags, authors, series, search, feeds, policy pages, and a sitemap. Lists paginate with `?page=2`; unavailable pages return 404. Post redirects return 301, and recorded removals return 410. Custom mount paths apply to all reader routes.

| Path | Content |
| --- | --- |
| `/blog`, `/blog?page=2` | Index with featured and ordinary cards |
| `/blog/:slug` | Article |
| `/blog/:slug.md` | Markdown text of the article |
| `/blog/category/:slug`, `/blog/tag/:slug`, `/blog/author/:slug`, `/blog/series/:slug` | List pages (segments follow `config.route_segments`) |
| `/blog/search?q=words`, `/blog/search.json?q=words` | Search page and suggestions |
| `/blog/feed.xml`, `/blog/feed.json`, `/blog/category/:slug/feed.xml`, `/blog/category/:slug/feed.json` | Atom and JSON Feed 1.1 |
| `/blog/sitemap.xml` | Sitemap, when `config.serve_sitemap` is true |
| `/blog/policies/:slug` | Published policy pages |
| `/blog/media/:sha256/:filename` | Original images |
| `/blog/preview/:token` | Signed previews of unpublished content |

## FAQ and Markdown text

FAQ records appear as expanded plain text after the article and supply its FAQ structured data. Blank lines create paragraphs, single line breaks remain visible, and bare HTTP(S) URLs become links. Markdown and HTML-looking text in FAQ answers stay literal.

`OpenBlog::MarkdownView.render(post)` returns a text version with truthful dates, notices, FAQs, and the canonical URL. The same text is served at `/blog/:slug.md` with canonical and noindex headers:

```sh
curl -s https://example.com/blog/garden-notes.md
```

```markdown
# Garden notes

Ada Example · Published October 03, 2026 · Updated October 03, 2026

Today in the garden, the beans came up.

https://example.com/blog/garden-notes
```

## Series and search

Readers can browse an ordered series at `/blog/series/:slug`; member articles link to the previous and next published article. Search at `/blog/search?q=words` covers titles, article text, and FAQ records. Queries must contain 2–100 characters. PostgreSQL uses ranked full-text search; SQLite matches every word. The sidebar offers live suggestions from `/blog/search.json` and also works as an ordinary search form without JavaScript. Search shares `config.search_rate_limit` across HTML and JSON requests per address (default 30 per minute).

```sh
curl -s "https://example.com/blog/search.json?q=garden"
```

```json
[
  {"title": "Winter garden", "url": "https://example.com/blog/winter-garden", "description": ""},
  {"title": "Garden notes", "url": "https://example.com/blog/garden-notes", "description": ""}
]
```

## Feeds and dates

Atom and JSON Feed 1.1 are available at `/blog/feed.xml` and `/blog/feed.json`, with category feeds under `/blog/category/:slug/feed.xml` and `.json`. Both use `config.feed_size` and `config.feed_content` (`:summary` or `:full`), and cache publicly for one hour. JSON summary entries include plain-text content.

```sh
curl -s https://example.com/blog/feed.json
```

```json
{
  "version": "https://jsonfeed.org/version/1.1",
  "title": "Blog",
  "home_page_url": "https://example.com/blog",
  "feed_url": "https://example.com/blog/feed.json",
  "items": [
    {
      "id": "https://example.com/blog/winter-garden",
      "url": "https://example.com/blog/winter-garden",
      "title": "Winter garden",
      "summary": "",
      "authors": [{"name": "Ada Example", "url": "https://example.com/blog/author/ada-example"}],
      "date_published": "2026-10-03T20:59:17Z",
      "date_modified": "2026-10-03T20:59:17Z",
      "content_text": ""
    }
  ]
}
```

Reader dates use publication history rather than database update timestamps. An adopted article with unknown historical dates omits those dates from the page and sitemap. Atom requires an `updated` value, so it uses the recorded adoption time until a substantive change or correction supplies a modification date. This fallback describes the available record, not a claimed original publication date. Maintenance does not advance that date.

`config.primary_list_type` selects categories or tags for indexing and sitemap inclusion. `OpenBlog.sitemap_entries` returns absolute URL entries for integration with a host sitemap; set `config.serve_sitemap = false` to disable the engine's `/blog/sitemap.xml` endpoint.

```ruby
OpenBlog.sitemap_entries(base_url: "https://example.com")
# => [{ loc: "https://example.com/blog" },
#     { loc: "https://example.com/blog/garden-notes", lastmod: 2026-10-03 20:59:05 UTC }, ...]
```

## Image delivery

Original images have stable URLs under `/blog/media/:sha256/:filename`. Redirect delivery caches only as long as the storage URL remains valid; `config.image_delivery = :proxy` serves immutable bytes with a one-year cache lifetime. Cards use Active Storage variants. Set `config.parent_controller` to inherit a host controller and its callbacks; the engine explicitly includes its helpers for custom parents.

## Policy pages

Policy pages use four fixed kinds: `responsible_party`, `corrections`, `editorial`, and `ai_use`. Save `title`, Markdown `body`, and `status` (`draft` or `published`) with [`PUT /pages/:kind`]({% link api.md %}#policy-pages) or the `blog_save_site_page` MCP tool. Optional fields are `slug`, `approved_by`, and an ISO date `approved_on`. A supplied nonblank approver defaults the omitted date to today; approval names are never filled automatically. Omitted fields retain their values. No policy text is supplied by the gem.

Published pages appear at `/blog/policies/:slug`, in the footer, and in the sitemap. Drafts return 404 publicly. `config.policy_urls[:kind]` can point to an existing host page; this overrides the local link and hides that kind's gem-hosted page. `OpenBlog.policy_url(kind)` resolves the configured URL or published local path, and returns `nil` when neither exists. Publishing or withdrawing the responsible-party page immediately updates relevant post notices without changing the posts' revision records or dates. Doctor checks configured URLs and recognizes published local pages.
