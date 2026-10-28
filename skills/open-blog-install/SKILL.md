---
name: open-blog-install
description: Install or upgrade Open Blog in a Rails host, reuse application navigation and colors, integrate the theme control, and diagnose setup compatibility.
---

## Locate the host and package

Work from the requested application's Rails root. Inspect its public layout and shared navbar/footer, CSS pipeline and palette variables, JavaScript entrypoint and Stimulus registration, existing theme preference, mount path, and editorial authentication. For a pilot, select isolated development/test databases before migrating.

Use the requested gem release; inspect `Gemfile.lock` and `bundle show open_blog`. The installed package is the authority for its version. Inside it, layout and reader templates are under `lib/generators/open_blog/install/templates/views/`, theme sources under `lib/generators/open_blog/install/templates/theme/`, and browser controllers under `app/assets/javascripts/open_blog/controllers/`.

For examples and explanations, read [host integration](https://techwright-lab.github.io/open-blog/host-integration/); for task/file routing, read [usage](https://techwright-lab.github.io/open-blog/usage/). In a source checkout these are `docs/host-integration.md` and `docs/usage.md`. The steps below remain usable from the installed gem without the documentation site.

## Check images before calling setup complete

- Inspect `active_storage_attachments.record_id` in the schema or with `ActiveStorage::Attachment.columns_hash.fetch("record_id").sql_type`. From 0.3.0 the migrations give Image and Author UUID keys when this column is `uuid`, and integer keys otherwise; doctor's Record keys check must report ok. A host that installed 0.2.0 on a UUID column needs `bin/rails railties:install:migrations FROM=open_blog` and `db:migrate` (the `AlignOpenBlogRecordKeys` migration). Keep the existing host attachment schema intact. With rich-text bodies, also follow doctor's Action Text key result; use Markdown when it reports a mismatch.
- Inspect the host variant processor before running the installer. It accepts `:vips` or `:mini_magick`; a disabled processor requires host configuration. Verify Ruby image-processing dependencies and native libvips/ImageMagick in the deployment image and production gem groups.
- Card and avatar variants use the engine's `/blog/media/:sha256/:variant/:filename` route and `config.image_delivery`, not the host's representation routes, so a host can keep those closed. Test originals and both variant URLs independently. Use `:proxy` when the host also blocks the storage service URLs that `:redirect` sends readers to. Preserve existing host access restrictions.

## Install and configure

Add a missing gem with `bundle add open_blog`, passing the requested version constraint when specified. On Rails 8.0, first run `bundle add json --version "< 3"`; Open Blog refuses to load on Rails 8.0 with JSON 3. For a fresh application, use `bin/rails generate open_blog:install`. For an existing application retaining its CSS pipeline, use `--skip-tailwind`. A staged local pilot can use:

```sh
bin/rails generate open_blog:install --theme=signal --skip-tailwind --skip-migrate --skip-sample
```

Choose the requested preset. These flags still write files, add dependencies, register JavaScript, and mount routes. Review migrations and the host diff, migrate the intended database, then run `bin/rails open_blog:doctor`. Create the initial token with `open_blog:install_token` only when the selected access method needs it; keep the one-time secret private. A configured authentication hook takes precedence over tokens. Run `open_blog:sample` only when sample publishing is wanted and image setup works.

Set actual publisher/author identities, public origin (including the local port for a pilot), mount path, and policy links in `config/initializers/open_blog.rb`. The public origin excludes the mount prefix. Keep `config.mount_path` and `config/routes.rb` consistent. Restart after initializer changes.

## Reuse application chrome

When shared navigation is requested, extract any inline public header/footer to host partials and render them in both the homepage and blog. Prefer a host-owned `app/views/layouts/blog.html.erb` with `config.layout = "blog"` when the main layout needs different behavior; `open_blog:views` does not overwrite that filename. Direct `config.layout = "application"` is also supported: branch on `@open_blog_page` for blog-specific head/assets. Layout selection is separate from `parent_controller`, whose inherited callbacks may require authentication or unavailable host state.

Adapt the installed layout while preserving `open_blog_theme_attributes`, `open_blog_head(@open_blog_page)`, early theme restoration, `open_blog_structured_data(@open_blog_page)`, `main#open-blog-main`, and the reader yield. Replace equivalent host head tags on reader requests so title/viewport/canonical are not duplicated. Keep host CSRF/CSP, icons, and required assets. Retain the reader's content/notices/byline/date helpers and policy/feed links, using a shared footer slot if needed. Host links in engine-rendered shared partials use `main_app`, for example `main_app.root_path`.

For `--skip-tailwind`/Tailwind 3, load the host's CSS explicitly and then `open_blog_stylesheets` (preset, compiled reader CSS, host override). For the Tailwind 4 component build, use `open_blog_theme_stylesheets` before the host build instead, keeping its generated `open_blog/theme.css` import. Register the `open-blog--` controllers in the public JavaScript entrypoint. Avoid `stylesheet_link_tag :all`; the compiled reader stylesheet contains reset rules. Scope `.ob-page` to the reader and inspect shared chrome after loading it.

## Share palette and appearance state

Use `config.theme_colors` for fixed hex colors. For host CSS variables, edit `app/assets/stylesheets/open_blog_theme.css` (fallback CSS) or `app/assets/tailwind/open_blog/theme.css` (Tailwind 4). Map semantic `--ob-*` colors to host tokens; `var()` is invalid in `theme_colors`. Override both explicit and system-mode specificity, for example the selector list `:root[data-ob-theme="signal"][data-theme], :root[data-ob-theme="signal"]:not([data-theme])`, loaded after preset rules. Cover surfaces, text, borders, accents, code, notices, and alerts. Keep Signal typography/shape if requested. Use opaque surface mixes where translucent host colors expose unwanted layers. Doctor does not check CSS-derived contrast.

Place a single theme button in the shared navbar if requested; it is not a separate nav. Reuse the existing `open-blog--theme` controller and `cycle` action, its `systemLabel`/`lightLabel`/`darkLabel` values, and optional `label` target. Keep the initial `hidden` attribute, accessible mode label, keyboard focus, and mobile target size. The installed `_theme_toggle.html.erb` shows its markup; a host partial can use host styles.

The controller stores `open-blog-theme` and sets `data-theme="light"` or `"dark"` on `<html>`; System removes both and follows the OS. Restore that same key before CSS loads on homepage and blog using the gem helper or one shared equivalent script with the host's CSP nonce. Keep one preference owner when the host already has a theme controller. Honor a fixed `config.color_scheme` by retaining its root attribute and omitting the toggle. Check Turbo transitions if used, full reloads, explicit light/dark, and system mode.

## Upgrade copied files deliberately

Read the target changelog, update any version constraint, then `bundle update open_blog --conservative`; review dependency changes too (on Rails 8.0, keep JSON below 3; Rails 8.1 can use JSON 3). Bundler does not refresh copied host files.

`bin/rails generate open_blog:views` refreshes reader templates and `layouts/open_blog.html.erb` only. Compare controllers, locales, and theme sources with the installed package separately. Conflicting files are kept in a noninteractive rerun; a successful generator exit does not mean all copies are current. Merge required changes and use replacement only for reviewed files. A blanket `open_blog:install --force` also replaces the initializer. Review a host-owned layout against new helper/asset contracts manually. When moving from 0.1.0 to presets, replace old full-palette definitions with intentional overrides so they do not mask the new preset. Rebuild affected assets and restart.

## Verify and report

Run doctor, relevant host regression tests, and real reader requests. Verify shared links/chrome, a single head/landmark, fonts and computed palette in all modes, preference persistence, keyboard access, and desktop/mobile overflow. Exercise a real upload and variant retrieval separately from text-only rendering; preserve host attachment regressions. Verify feeds/sitemap and any promised scheduling with the actual worker, not only a direct job invocation.

For MCP use, check `tools/list` and make an authenticated `blog_list_posts` call when that access is configured. Exercise draft privacy and signed previews; perform publication/edit checks within authorized local/test scope. Report observed passes, blockers, and unverified checks separately. Installation does not authorize unrelated content publication or production deployment.
