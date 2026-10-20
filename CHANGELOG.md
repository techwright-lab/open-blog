# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0]

### Added

- Support hosts whose `active_storage_attachments.record_id` is a UUID. The migrations read that column and give `open_blog_images` and `open_blog_authors` UUID primary keys, with UUID `author_id`, `cover_image_id`, and `social_image_id` post references, when it is a UUID. Integer-keyed hosts keep integer keys. No host table changes and no setting.
- Add the `AlignOpenBlogRecordKeys` migration. It converts the image and author keys of a 0.2.0 installation on a UUID attachment table and keeps every row and reference; on an integer-keyed host it does nothing.
- Add the doctor **Record keys** check. It reports blog keys that cannot be attachment records, and, with rich-text bodies enabled, Action Text keys that do not match the post or attachment keys.
- Serve card thumbnails and author avatars from the engine route `/blog/media/:sha256/:variant/:filename` (`card` or `avatar`), delivered through `config.image_delivery` like the originals.

### Changed

- Card and avatar images no longer use the host's Active Storage representation routes, so a host can keep `ActiveStorage::Representations::RedirectController` and `ProxyController` closed.
- On a UUID-keyed host, `image_id` and author `id` values in the JSON API and MCP tool schemas are UUID strings.

### Upgrade notes

- Run `bin/rails railties:install:migrations FROM=open_blog` and `bin/rails db:migrate`; doctor reports an error until `AlignOpenBlogRecordKeys` has run. On an integer-keyed host the migration makes no schema change.
- Copied reader templates need no change: `open_blog_card_image` and `open_blog_avatar` emit the new URLs. A host template that builds its own variant URL with `main_app.url_for` still needs the host's representation routes.
- JSON stays below version 3: Rails 8.0 does not work with JSON 3.

## [0.2.0] - 2026-10-10

### Added

- Add a Usage guide and an existing-host integration recipe covering shared layouts, application colors, theme controls, image compatibility, and copied-file upgrades; expand the packaged install skill and document agent skill loading.
- Add three reader presets, Signal, Editorial, and Ink, selected with `config.theme`. Each has light and dark values that meet WCAG 2.2 AA contrast.
- Ship the preset fonts (Outfit, DM Sans, Newsreader, Space Grotesk, and JetBrains Mono) as woff2 files with their license texts. No font loads from another site.
- Add `config.theme_colors` for hex color overrides of the preset, for both modes or per mode. Doctor warns when an override takes a text and background pair below 4.5:1; a translucent color is measured over the color under it.
- Add the `--theme=signal|editorial|ink` installer option.
- Collapse FAQ entries into `<details>` elements by default; `config.faq_collapsed = false` keeps every answer visible.
- Add a Themes guide with the presets, palette overrides, the token reference, and fonts.

### Changed

- The default look is the Signal preset in place of the blue slate theme.
- The copied token file is now an override stub. Token values come from the preset stylesheet `open_blog/themes.css`, which the gem serves in every host setup.

### Fixed

- Wait for RubyGems to index a pushed version before tagging the release, instead of refusing the tag.
- Update the existing policy page when two first writes to `PUT /api/v1/pages/:kind` race, instead of answering one of them with `422 validation_failed`.

### Upgrade notes

- The default look of a 0.1.0 host changes to the Signal preset. A `--skip-tailwind` or Tailwind 3 host gets it when the gem is updated. A Tailwind 4 host gets it after its copied stylesheets and layout are refreshed, as the next two notes show. A host that edited its copied tokens sets `config.theme = :none` to keep them, or moves its hex values to `config.theme_colors`.
- In a Tailwind 4 host, the copied `app/assets/tailwind/open_blog/blog.css` and `theme.css` are the 0.1.0 files, with no preset rules and no styles for the collapsed FAQ. `bin/rails generate open_blog:install` keeps files that exist, so delete these two files and then run it; doctor gives a warning until `blog.css` is replaced. Do not use `--force` on a configured host, because it also replaces `config/initializers/open_blog.rb`.
- In a Tailwind 4 host, the blog layout must call `open_blog_theme_stylesheets` before the host stylesheet tag, or `bin/rails open_blog:doctor` reports an error. `bin/rails generate open_blog:views --force` writes that layout.
- FAQ entries are now collapsed. Set `config.faq_collapsed = false` for the 0.1.0 markup.
- The [Themes guide](https://techwright-lab.github.io/open-blog/themes/#upgrade-from-010) lists each step.

## [0.1.0] - 2026-10-03

### Added

- Publish searchable public documentation with installation, configuration, publishing, API, MCP, and customization guides.
- Prepare release pull requests that update the version and dated changelog, then publish verified packages to RubyGems and synchronize GitHub Releases.

- Initial gem package, runtime dependencies, tests, and continuous integration.
- Add a mountable engine with validated configuration and a PostgreSQL/SQLite host test matrix.
- Add content models, reversible database migrations, deterministic revision identifiers, and immutable publishing records.
- Add transactional draft, publish, approve, unpublish, and remove operations with publication history and scheduled enqueueing.
- Record direct FAQ and rich-text changes atomically and return advisory findings and AI notice labels from publishing operations.
- Import existing articles with source identity, historical dates, declared or imported approvals, redirects, safe repeat handling, and transactional dry runs.
- Reuse signed Active Storage blobs for imported images and extract proposed FAQ sections from Markdown with review findings.
- Render sanitized Markdown and rich text with heading links, syntax highlighting, image figures, body findings, durable image identities, and generated light/dark syntax colors.
- Add reader routes and copied templates for the layout, header, footer, sidebar, featured and ordinary cards, pagination, breadcrumbs, sharing, author box, call to action, related posts, post highlights, table of contents, tags, index, post, category, tag, author, and missing-page views.
- Add reader metadata, structured data, publication dates, notices, Atom feeds, sitemap entries, redirects, and stable original-image delivery.
- Add responsive light/dark themes, configurable design tokens, accessible syntax colors, and a reproducible compiled stylesheet.
- Add theme selection, link and code copying, device sharing, table-of-contents tracking, reading progress, and browser accessibility checks.
- Render ordered FAQ records as visible plain text and FAQ structured data, with a shared table-of-contents anchor and Markdown text output.
- Add install and views generators, an idempotent sample article, installation diagnostics, and fresh-application compatibility checks.
- Add scoped API tokens and authenticated JSON endpoints for posts, approvals, connection declarations, publishing history, findings, and installation checks.
- Add bounded remote image imports, deduplicated uploads, supporting-record APIs, adoption previews, FAQ extraction, redirect serialization, and one-time installer tokens.
- Add stateless MCP publishing tools, shared API validation, revision-bound preview links, and packaged agent workflows.
- Add editable policy pages with scoped API and MCP access, public rendering, footer and sitemap links, and live notice and diagnostic updates.
- Add series navigation, ranked reader and API search, live search suggestions, Markdown responses, and JSON Feed 1.1.
- Execute due publication schedules safely, count anonymous daily page views, expose view reports and a popular-post sidebar, and check internal blog links.
- Add page and publishing-record reports with JSON, text, MCP, and Rails-task access, plus optional bounded reach checks.
- Add an optional AdminSuite generator with isolated resources, nested FAQ editing, and read-only publishing-history panels.

### Upgrade notes

- This is the first packaged release. Existing Git-source installations should run `bin/rails open_blog:install:migrations` and `bin/rails db:migrate` before restarting application and job processes.
- Reader templates are copied into the host. Run `bin/rails generate open_blog:views` to review updates; preserve local customizations and deliberately accept replacements. Refresh installed browser controllers with the install generator when upgrading from an earlier development checkout.
- Configure the public origin, publisher identity, policy pages, storage, and authentication for your deployment. The sample article is demonstration content and has no human approval record.
- Applications writing through bulk SQL must move to normal model saves or publishing operations to retain revision history.

