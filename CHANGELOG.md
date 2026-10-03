# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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
