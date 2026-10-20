---
layout: default
title: Usage
nav_order: 2.1
permalink: /usage/
---

# Usage

Open Blog runs inside your Rails application. The gem owns the publishing operations, records, reader helpers, and API/MCP endpoints. Your application owns the mount, configuration, copied reader templates, assets, authentication integration, and deployment.

For a new application, start with [installation]({% link installation.md %}). For an existing application whose navigation, footer, and colors should carry through to the blog, follow [integrating with your application]({% link host-integration.md %}). That guide includes the setup sequence, layout example, theme control, image compatibility checks, and upgrade procedure.

## Choose a publishing interface

| Interface | Where to use it | Start here |
| --- | --- | --- |
| Ruby | Rails console, host services, jobs, or your own editor | [Publishing operations]({% link publishing.md %}) |
| JSON API | An HTTP client or another application | [API and authentication]({% link api.md %}) |
| MCP | An agent connected to the running host | [MCP and agents]({% link mcp.md %}) |
| AdminSuite | An optional browser editor in the host | [Generate admin resources]({% link admin-suite.md %}) |

The default installation provides reader pages. It does not install a standalone editorial dashboard. Installing the gem also does not register its packaged skills with your agent client; see [loading the workflows]({% link mcp.md %}#packaged-agent-workflows).

## Work through an article's lifecycle

1. Configure the real publisher, public origin, author, and access method. Complete the [policy pages]({% link reader.md %}) using the publisher's actual practices.
2. Save a draft, inspect its findings, and open its signed preview. An unpublished draft is not a public article.
3. Review the exact content, record only approval and fact-checking that actually occurred, then publish or schedule it within the requested scope. [Publishing]({% link publishing.md %}) explains provenance and revision-bound approval.
4. Verify the reader page, metadata, feeds, and images. A scheduled response also needs a working job worker or recurring publication task.
5. For a public edit, choose `substantive`, `correction`, or `maintenance`. Public edits take effect immediately; there is no separate unpublished copy of an already-public post. See [editing and revisions]({% link publishing.md %}).
6. Run [diagnostics and surface reports]({% link diagnostics.md %}) when investigating setup or rendered content. Preserve the distinction between passed, failed, and unverified checks.

For existing articles, use [adoption]({% link adoption.md %}) to preserve historical evidence and redirects instead of publishing them as newly written posts.

## Where do I change it?

Paths below are relative to the Rails host, except for the last row.

| Question | Location or setting |
| --- | --- |
| Site name, publisher, author, public origin? | `config/initializers/open_blog.rb`; [configuration reference]({% link configuration.md %}) |
| Blog URL prefix? | The engine mount in `config/routes.rb` and matching `config.mount_path` |
| Application navbar and footer? | Host shared partials rendered by the layout named in `config.layout`; [layout recipe]({% link host-integration.md %}#share-the-application-layout) |
| Article, card, sidebar, or list markup? | Copied templates in `app/views/open_blog/` |
| Signal, Editorial, or Ink? | `config.theme`; [themes]({% link themes.md %}) |
| Fixed brand colors? | Hex values in `config.theme_colors` |
| Existing application color variables or fonts? | Generated theme override CSS; [map the host palette]({% link host-integration.md %}#map-the-host-palette) |
| Theme button and saved mode? | Shared navbar partial, `open-blog--theme` controller, and early theme restoration; [one shared theme control]({% link host-integration.md %}#use-one-shared-theme-control) |
| Browser behavior? | Copied `app/javascript/controllers/open_blog/` and the host's Stimulus registration |
| Reader translations? | Copied `config/locales/open_blog.en.yml` and host locale files |
| Image processing and delivery? | Host Active Storage schema, service, processor, and routes; `config.image_delivery` selects original-image delivery |
| Agent instructions? | `skills/open-blog-*/SKILL.md` inside the installed gem; locate it with `bundle show open_blog` |

## Common questions

**Why does the blog initially have its own navbar and footer?** The generated layout is a complete standalone reader because the installer cannot know your application's partials. Select a host-owned layout and reuse the same shared partials. A theme preset only changes styling; it does not discover or replace application navigation.

**Can I use `application.html.erb` directly?** Yes: set `config.layout = "application"`, then make it handle blog metadata, assets, and theme attributes on reader requests. A separate `blog.html.erb` using shared site partials is often easier when the application's authenticated pages and public pages differ. [Both choices are explained here]({% link host-integration.md %}#share-the-application-layout).

**Do these changes require a fork?** Shared navigation, a host palette, and a relocated theme control use existing extension points. Keep them in the host. Storage incompatibilities are a separate concern: an attractive reader page does not establish that uploads and variants work.

**Why didn't updating the gem update my reader files?** Copied files belong to your application. Bundler updates the package; it does not replace those files. Review and refresh them using the [upgrade procedure]({% link host-integration.md %}#upgrade-without-losing-host-customizations).

**Does a passing doctor mean setup is complete?** Doctor checks selected configuration and source files. It compares blog record keys with the host attachment table, but it does not perform a real image upload or verify the appearance of a custom layout. Use the [acceptance checks]({% link host-integration.md %}#verify-the-integration) too.
