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
