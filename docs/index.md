---
layout: default
title: Open Blog
nav_order: 1
permalink: /
---

# Open Blog

Open Blog is an agentic blog engine for Rails 8, with Markdown and rich-text articles, revision history, responsive reader pages, and authenticated publishing through Ruby, JSON, and MCP. It supports PostgreSQL and SQLite.

[Install Open Blog]({% link installation.md %}){: .btn .btn-primary }
[Browse the source](https://github.com/techwright-lab/open-blog){: .btn }

Open Blog runs on Ruby 3.2 to 4.0 with Rails 8.0 or 8.1; the [installation guide]({% link installation.md %}#requirements) lists the full requirements. Install from GitHub for the latest source. See [GitHub Releases](https://github.com/techwright-lab/open-blog/releases) for published versions and their release notes.

## Start here

- [Installation]({% link installation.md %}): mount the engine and generate your first article.
- [Configuration]({% link configuration.md %}): every setting with its default.
- [Publishing]({% link publishing.md %}): drafts, revisions, previews, and scheduled releases.
- [JSON API]({% link api.md %}) and [MCP]({% link mcp.md %}): publish from clients and agents.
- [Customization]({% link customization.md %}): reader views, colors, assets, and rendering.
- [Adoption]({% link adoption.md %}): import existing articles and their history.

## Reader themes

The included reader adapts to phones and desktops and supports light and dark themes.

![Open Blog reader in the light theme]({{ "/assets/images/reader-light.png" | relative_url }})

![Open Blog reader in the dark theme]({{ "/assets/images/reader-dark.png" | relative_url }})

Open Blog is distributed under the [MIT License](https://github.com/techwright-lab/open-blog/blob/main/LICENSE.txt).
