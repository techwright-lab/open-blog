---
layout: default
title: Diagnostics
nav_order: 11
permalink: /diagnostics/
---

# Diagnostics

## Installation checks

Run `bin/rails open_blog:doctor` to inspect configuration, assets, routes, storage, and publishing records. Errors return exit status 1; warnings identify setup still needed. The read-scoped API `GET /blog/api/v1/doctor` and MCP `blog_doctor` expose the same checks.

## Surface reports

Inspect live reader pages and their publishing records with `bin/rails open_blog:report SCOPE=post POST=article-slug`, the read-scoped `GET /blog/api/v1/report?scope=post&post=article-slug`, or MCP `blog_get_surface_report`. The API returns JSON; use `Accept: text/plain` or `format=text` for text. Scope `site` checks site-wide pages, feeds, lists, and redirects. Scope `post` adds one public article; `all` checks public articles in batches of 50 using `page` (or task `PAGE`). Each result includes the inspected IDs and pagination totals.

Set `config.public_base_url` to the running host. Reports fetch the rendered pages and compare visible fields, metadata, dates, links, image bytes, FAQ content, approvals, and disclosures with stored records. Results distinguish `pass`, `fail`, `not applicable`, and `not verified`, and include evidence and explicit limits. They do not certify editorial quality. Missing configuration, unavailable evidence, and exhausted request budgets remain unverified. Browser layout, manual accessibility review, and field performance are listed separately as checks not run.

Set `reach=true` (task `REACH=true`) to also check crawler access, HTTP-to-HTTPS upgrades, and same-site link destinations. Requests identify themselves as a bot and do not add page views. Fetches are bounded by time and size, reject private network destinations outside the configured origin, and stop starting requests after 60 seconds, 500 distinct URLs, or 32 MiB of completed response bodies. Narrow the scope when a report reaches a limit. The configured origin is trusted so local and private hosts can inspect themselves.
