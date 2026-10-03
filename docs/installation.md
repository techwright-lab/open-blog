---
layout: default
title: Installation
nav_order: 2
permalink: /installation/
---

# Installation

## Requirements

| Requirement | Supported |
| --- | --- |
| Ruby | 3.2, 3.3, 3.4, or 4.0 |
| Rails | 8.0 or 8.1 |
| Database | PostgreSQL or SQLite |
| Images | Active Storage with libvips (or ImageMagick if your host uses that backend) |
| Rich text | Action Text, only when `body_formats` includes `:rich_text` |

Every combination of Ruby, Rails, and database above runs in CI. Install from GitHub until a version is published on RubyGems:

```sh
bundle add open_blog --github techwright-lab/open-blog
bin/rails generate open_blog:install
```

Start the host with `bin/dev` (or `bin/rails server`) and open `/blog`. Set your site and author names in the generated initializer, or pass `--site-name="My Journal" --author-name="Example Author"` to the generator.

The generator installs the tables, mounts `/blog`, copies reader views and browser controllers, and publishes one sample article. When the host has no authentication hook or existing token, it prints one API token; save the secret because repeated installation will not show it again. It detects importmap or a JavaScript bundler and Tailwind 4. If Tailwind is absent, its installer also changes the host's application layout and development scripts. Use `--skip-tailwind` to keep the host's CSS setup and load the gem's compiled stylesheet only in the blog layout.

## Generator options

| Option | Default | Effect |
| --- | --- | --- |
| `--site-name`, `--author-name` | placeholders | Values written to the initializer. |
| `--mount-at=/journal` | `/blog` | Mount path. Part of every post URL, so choose it before publishing. |
| `--mount-position=first` | `last` | Place the mount before existing host routes. The default keeps host routes first. |
| `--body-format=rich_text` | `markdown` | Permitted body formats: `markdown`, `rich_text`, or `both`. |
| `--skip-sample` | | Do not publish the sample article. |
| `--skip-migrate` | | Copy migrations without running them. The sample and token are deferred; run `bin/rails open_blog:sample` and `bin/rails open_blog:install_token` after migrating. |
| `--skip-tailwind` | | Keep the host's CSS setup and load the gem's compiled stylesheet. |
| `--admin-suite` | | Also run the [AdminSuite generator]({% link admin-suite.md %}). |
| `--force` | | Replace changed copied files. Without it, changed files are kept in a noninteractive terminal. |

Repeating installation reuses the sample and migrations. `bin/rails generate open_blog:views` refreshes only the copied views.

## Configure your site

Run `bin/rails open_blog:doctor` to inspect configuration, assets, routes, storage, and publishing records. Errors return exit status 1; warnings identify setup still needed.

Set your public origin and replace the placeholder identities in `config/initializers/open_blog.rb`. The [configuration reference]({% link configuration.md %}) lists every setting with its default. The copied templates live in the host's `app/views/open_blog`; see [customization]({% link customization.md %}) for reader assets.
