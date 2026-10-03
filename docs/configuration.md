---
layout: default
title: Configuration
nav_order: 3
permalink: /configuration/
---

# Configuration

Edit `config/initializers/open_blog.rb` in your host application. The installer writes this file with the required settings and a few common choices. Every other setting keeps the default shown below until you set it.

```ruby
OpenBlog.configure do |config|
  config.site_name = "My Journal"
  config.public_base_url = "https://example.com"
  config.default_author = { name: "Example Author", type: :person }
  config.publisher = { name: "My Company", url: "https://example.com" }
end
```

`site_name`, `default_author`, and `publisher` are required. `public_base_url` is required in production. Settings are validated at application boot, and an invalid value raises `OpenBlog::ConfigurationError` with the setting name.

## Identity and site text

| Setting | Default | Purpose |
| --- | --- | --- |
| `site_name` | required | Name used in page titles, feeds, and structured data. |
| `public_base_url` | `nil` | Public origin (`https://example.com`) for canonical URLs, sitemaps, previews, and fetched reports. Scheme, host, and optional port only. |
| `default_author` | required | `{ name:, type: :person or :organization, url:, logo_url: }` used when a post names no author. |
| `publisher` | required | `{ name:, url:, logo_url: }` recorded as the responsible publisher. |
| `locale` | `I18n.default_locale` | Locale for reader pages, dates, and the `lang` attribute. |
| `blog_title` | `"Blog"` | Breadcrumb and index heading. |
| `blog_tagline` | `nil` | Optional line under the index heading; also the index description. |
| `title_suffix` | `" — #{site_name}"` | Appended to every page title. Set `""` to remove it. |
| `default_social_image_url` | `nil` | Social image for posts without a cover or social image. |
| `call_to_action` | `nil` | `{ title:, text:, label:, url: }` rendered after each article. |
| `policy_urls` | all `nil` | `{ responsible_party:, corrections:, editorial:, ai_use: }`. A host URL overrides the gem-hosted policy page of that kind. |
| `sign_in_destinations` | `nil` | Path prefixes that lead to a sign-in page, declared for the surface report's link checks. `[]` declares none. |

## Routes and reader pages

| Setting | Default | Purpose |
| --- | --- | --- |
| `mount_path` | `"/blog"` | Must match the `mount` line in `config/routes.rb`. Part of every post URL and redirect record, so change it before publishing. |
| `route_segments` | `{ category: "category", tag: "tag", author: "author", series: "series" }` | URL segments for list pages. Their values are reserved slugs. |
| `layout` | `"open_blog"` | Host layout rendered by reader controllers. |
| `parent_controller` | `"ActionController::Base"` | Host controller the reader controllers inherit from. The engine includes its helpers for any parent. |
| `posts_per_page` | `12` | Page size for the index and list pages. |
| `primary_list_type` | `:categories` | `:categories` or `:tags`: which list pages are indexed and placed in the sitemap. |
| `serve_sitemap` | `true` | Serve `/blog/sitemap.xml`. Set `false` and use `OpenBlog.sitemap_entries` in a host sitemap. |
| `color_scheme` | `:system` | `:system`, `:light`, or `:dark`. |
| `syntax_theme` | `"github"` | Rouge theme for code blocks. `"base16"` and `"gruvbox"` also support both modes. |
| `feed_content` | `:summary` | `:summary` or `:full` for Atom and JSON Feed entries. |
| `feed_size` | `20` | Entries per feed. |

## Content and publishing

| Setting | Default | Purpose |
| --- | --- | --- |
| `body_formats` | `[:markdown]` | Permitted formats: `:markdown`, `:rich_text`, or both. |
| `default_body_format` | `:markdown` | Format for posts that do not name one. Must be in `body_formats`. |
| `markdown_hardbreaks` | `true` | Treat single line breaks in Markdown as `<br>`. |
| `ai_label` | `:when_required` | `:when_required` shows the AI notice until a facts-checked approval, a responsible-party page, and image digests exist. `:always` keeps it on every AI-assisted post. |
| `require_approval` | `false` | Refuse to publish a post that is not `human_written` unless the current revision has a facts-checked approval. Scheduled releases are exempt. |
| `before_publish` | `nil` | Callable receiving `(post, context)`. Return an array of messages to refuse with `refused_by_host`, or `nil` to allow. `context` holds `:actor`, `:now`, and `:attributes`. |
| `preview_expires_in` | `7.days` | Preview link lifetime. Changing it invalidates existing links. |

```ruby
config.require_approval = true
config.before_publish = ->(post, context) do
  [ "Add a category before publishing." ] if post.category.nil?
end
```

## Images

| Setting | Default | Purpose |
| --- | --- | --- |
| `storage_service` | host default | Active Storage service name for gem images. |
| `image_delivery` | `:redirect` | `:redirect` sends readers to the storage URL. `:proxy` serves the bytes with a one-year cache lifetime. |
| `max_image_bytes` | `10.megabytes` | Limit for uploads, URL imports, and MCP base64 input. |
| `image_content_types` | PNG, JPEG, WebP, GIF, AVIF | Accepted types. SVG is always refused. |
| `image_fetch_policy` | `:public_only` | `:open` also allows private network addresses for URL imports. Doctor warns when set. |

## Access and limits

| Setting | Default | Purpose |
| --- | --- | --- |
| `authenticate` | `nil` | Callable receiving the request. Return an object with `name`, optional `scopes`, and optional `id`, or `nil` to refuse. When set, API tokens are not used. |
| `api_rate_limit` | `{ to: 120, within: 1.minute }` | Requests per actor across the JSON API and MCP. |
| `search_rate_limit` | `{ to: 30, within: 1.minute }` | Search requests per address across HTML and JSON. |
| `rate_limit_store` | `Rails.cache` | Cache store for both limits. Use a shared store when several processes serve requests. |
| `mcp.enabled` | `true` | Serve `/blog/mcp`. |
| `mcp.max_page_size` | `50` | Maximum list size an MCP tool returns. |

```ruby
config.authenticate = ->(request) do
  user = request.env["warden"]&.user
  OpenBlog::Actor.new(name: user.name, scopes: user.editor? ? %w[read write publish] : %w[read], id: user.id) if user
end
```

## Page views

| Setting | Default | Purpose |
| --- | --- | --- |
| `page_views` | `true` | Count daily article views. |
| `page_view_bot_pattern` | `OpenBlog::PageViews::BOT_PATTERN` | Regular expression for User-Agent values to exclude. |
| `page_view_retention_days` | `nil` | Rows older than this are removed by `bin/rails open_blog:prune_page_views`. |
| `popular_posts` | `{ enabled: false, days: 30, limit: 5 }` | Popular-article sidebar. |

Scheduled publishing needs a durable Active Job adapter or the recurring `open_blog:publish_due` task. See [API authentication]({% link api.md %}#authentication), [reader routes and feeds]({% link reader.md %}), [analytics]({% link analytics.md %}), and [diagnostics]({% link diagnostics.md %}) for detailed behavior.
