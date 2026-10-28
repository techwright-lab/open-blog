---
layout: default
title: Integrating with your application
nav_order: 8.1
permalink: /host-integration/
---

# Integrating with your application

This guide describes using Open Blog with an existing Rails application's navigation, footer, palette, and JavaScript. The workflow comes from a real host integration using the published 0.2.0 gem and Signal. The visual integration required only host changes. That host's UUID attachment table and closed representation routes led to the record-key and image-variant support in 0.3.0.

## Inspect the host before installation

Work from the Rails root (for example, `backend/` in a monorepo). Identify:

- The public layout, navbar/footer partials, CSS entry point, and existing theme preference.
- Importmap or the JavaScript bundler, the public JavaScript entry point, and how it registers Stimulus controllers.
- The desired mount path, public origin, and whether an existing authentication hook or scoped blog tokens will serve editorial clients.
- The Active Storage service, attachment ID types, variant processor, native libraries in the deployment image, and restrictions on blob/representation routes.

For a pilot, select isolated development and test databases before migrating. Existing applications may already have Active Storage and Action Text tables; inspect the generated migrations and schema diff before applying them.

### Image compatibility is a separate check

Active Storage stores each attachment's owner in the polymorphic `active_storage_attachments.record_id` column, so blog images and authors need primary keys of the same type. Inspect the actual column, not the keys of other host models:

```ruby
ActiveStorage::Attachment.columns_hash.fetch("record_id").sql_type
```

Open Blog reads this column when its migrations run. When `record_id` is `uuid`, the migrations create `open_blog_images` and `open_blog_authors` with UUID primary keys, and the post columns that reference them (`author_id`, `cover_image_id`, `social_image_id`) as UUIDs. Otherwise they keep the Rails default integer keys. The host's attachment tables and IDs stay as they are, and no setting is needed. `bin/rails open_blog:doctor` reports a mismatch in its **Record keys** check.

On a UUID-keyed host, image and author IDs in the JSON API and MCP tools are UUID strings, for example `"cover_image": { "image_id": "4f0c…" }`. Post IDs stay integers.

A host that installed 0.2.0 on a UUID attachment table has integer blog keys, and its uploads fail with `ActiveRecord::NotNullViolation`. Install the 0.3.0 migrations and run them. The `AlignOpenBlogRecordKeys` migration converts the two tables and the post references to UUIDs and keeps every existing row and link. On an integer-keyed host the same migration changes nothing.

```sh
bin/rails railties:install:migrations FROM=open_blog
bin/rails db:migrate
bin/rails open_blog:doctor
```

Rich-text bodies are records of the host's Action Text table, so they have one more requirement. With `config.body_formats` including `:rich_text`, `action_text_rich_texts.record_id` must match the blog post key (integer), and `action_text_rich_texts.id` must match `active_storage_attachments.record_id` for embedded images. Doctor reports both. When the host tables do not match, use Markdown bodies; do not change the host's Action Text table only for the blog.

The installer accepts `:vips` or `:mini_magick` as the host's variant processor. A host that disabled variants must choose and configure a supported processor before installation. For vips, the Ruby dependencies (`image_processing` and `ruby-vips`) and native libvips must be available in the actual deployment image, including production gem groups.

### Image variants do not use the host's representation routes

Card thumbnails and author avatars come from the engine route `/blog/media/:sha256/:variant/:filename`. It serves only the `card` (640×360) and `avatar` (80×80) variants of stored blog images, and it follows `config.image_delivery`, the same setting as the original images:

| `config.image_delivery` | Originals and variants |
| --- | --- |
| `:redirect` (default) | Redirect to the storage service URL for the processed file |
| `:proxy` | Serve the bytes from the engine with a one-year immutable cache lifetime |

A host can keep `ActiveStorage::Representations::RedirectController` and `ProxyController` closed. With `:redirect` and the Disk service, the redirect goes to Active Storage's disk route; on a cloud service it goes to a signed bucket URL. If a host also closes those, use `:proxy`. An avatar attached directly from a blob that is not a blog image still uses `main_app.url_for` and needs the host's representation routes; avatars set through the API or MCP tools are always blog images.

## Install in stages

For an existing host that will keep its CSS pipeline, this is the staged installation used by the pilot:

```sh
bundle add open_blog --version 0.2.0
bin/rails generate open_blog:install --theme=signal --skip-tailwind --skip-migrate --skip-sample
```

`0.2.0` is the reproducible pilot version, not an instruction to hold every application on it. Use the release requested for your integration. The ordinary [installation guide]({% link installation.md %}) uses the latest release allowed by Bundler.

`--skip-tailwind` keeps the existing CSS setup and uses the gem's compiled reader stylesheet; it is useful even when the host already uses Tailwind. `--skip-migrate` copies migrations without applying them and defers token/sample creation. `--skip-sample` avoids creating the illustrated sample. These flags still allow the installer to add dependencies, install JavaScript support, write files, and mount the engine.

Review those changes, configure the correct databases, and then run:

```sh
bin/rails db:migrate
bin/rails open_blog:doctor
```

Run `bin/rails open_blog:install_token` when the chosen access method needs the initial token; store its one-time secret securely. Run `bin/rails open_blog:sample` only when sample publishing is wanted and image setup works. Skipping the sample is not evidence that uploads work.

Set real identity and origin values in `config/initializers/open_blog.rb`, preserving other generated settings:

```ruby
config.theme = :signal
config.layout = "blog"
config.site_name = "Example"
config.default_author = { name: "Example", type: :organization }
config.publisher = { name: "Example", url: "https://example.com" }
config.public_base_url = ENV.fetch("OPEN_BLOG_PUBLIC_BASE_URL", "https://example.com")
```

The environment variable above is a host convention defined by this example, not a built-in gem setting. For a local pilot, set it to the running origin including its port. The origin does not include `/blog`; the route mount and `config.mount_path` define that prefix. Restart the server after initializer changes.

## Share the application layout

The default `config.layout = "open_blog"` selects the generated standalone layout. The installer cannot infer your application's header or footer.

Choose either:

- **A host-owned blog layout:** create `app/views/layouts/blog.html.erb`, set `config.layout = "blog"`, and reuse the same site partials as the homepage. This keeps the layout outside the `open_blog:views` generator's output paths.
- **The application layout:** set `config.layout = "application"` and add blog-specific metadata, assets, and theme attributes on reader requests. Preserve the ordinary application's head on its other requests. Reader controllers expose `@open_blog_page` for this branch.

Extract an inline homepage navbar into a shared partial first if necessary. Selecting a layout does not require changing `config.parent_controller`. Inheriting from your `ApplicationController` is a separate choice that also brings its callbacks, authentication, and assumptions into reader requests.

For the staged `--skip-tailwind` installation, this is a minimal host-owned layout. Adapt the host asset name, JavaScript tag, and partial names to the application:

```erb
<!DOCTYPE html>
<%= tag.html(lang: open_blog_lang, **open_blog_theme_attributes) do %>
  <head>
    <meta charset="utf-8">
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>
    <%= open_blog_head(@open_blog_page) %>
    <%= open_blog_theme_script %>
    <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
    <%= open_blog_stylesheets %>
    <%= javascript_importmap_tags %>
    <%= open_blog_structured_data(@open_blog_page) %>
  </head>
  <body>
    <%= render "shared/site_header" %>
    <div class="ob-page">
      <main id="open-blog-main" class="ob-main"><%= yield %></main>
    </div>
    <%= render "shared/site_footer" %>
  </body>
<% end %>
```

A `tailwindcss-rails` host commonly names its built asset `"tailwind"` rather than `"application"`. For a JavaScript bundler, use its existing script tag instead of `javascript_importmap_tags`, and register the copied `open-blog--` controllers in that entry point.

If you installed the gem's components into the host's Tailwind 4 build instead of using `--skip-tailwind`, call `open_blog_theme_stylesheets` **before** the host CSS tag and omit `open_blog_stylesheets`. Keep the generated `open_blog/theme.css` import in the build. See [the two asset paths]({% link customization.md %}#themes-and-stylesheets).

Keep these contracts when adapting either layout:

| Element | Why it is needed |
| --- | --- |
| `open_blog_theme_attributes` on `<html>` | Selects the preset and any fixed color mode |
| `open_blog_head(@open_blog_page)` | Owns the blog title, description, canonical URL, robots, viewport, social metadata, feed discovery, and theme-color tags; replace equivalent host tags on blog requests to avoid duplicates |
| Early `open_blog_theme_script` or equivalent shared restoration | Restores the saved mode before styles paint |
| Correct CSS helper and public JavaScript entry point | Loads reader styles, fonts, and browser behavior |
| `open_blog_structured_data(@open_blog_page)` | Keeps article, breadcrumb, and FAQ structured data |
| One `main#open-blog-main` and the reader `yield` | Preserves the reader landmark and skip-link destination |
| Reader content helpers in the copied templates | Preserve notices, bylines, dates, cover images, and policy disclosure |

Use `main_app.root_path` and other `main_app` helpers for host links in shared partials. Inside a mounted engine, an unqualified `root_path` can point back to the blog. Use the gem's reader helpers for blog destinations. Retain policy and feed links in the shared footer, for example through a `content_for` slot populated only by the blog layout; the generated `open_blog/shared/_footer.html.erb` provides the existing link logic.

Wrapping reader content in `.ob-page` lets the header/footer retain host styling. The compiled stylesheet also contains global reset rules, so inspect the shared chrome in the browser. Load reader assets explicitly on the pages that need them; `stylesheet_link_tag :all` can leak the blog reset into unrelated pages.

## Map the host palette

Selecting Signal does not inherit the application's colors. Use `config.theme_colors` for literal hex colors, or the generated override stylesheet for aliases to existing host CSS variables. `var()` and `color-mix()` are not accepted by `config.theme_colors`.

| Installation | Host override file |
| --- | --- |
| `--skip-tailwind` or Tailwind 3 | `app/assets/stylesheets/open_blog_theme.css` |
| Tailwind 4 component build | `app/assets/tailwind/open_blog/theme.css` |

Example aliases follow. Replace `--app-*` with variables defined by your application. The host variables must already switch in explicit light, explicit dark, and system mode.

```css
:root[data-ob-theme="signal"][data-theme],
:root[data-ob-theme="signal"]:not([data-theme]) {
  --ob-surface: var(--app-background);
  --ob-surface-raised: color-mix(in srgb, var(--app-background), var(--app-text) 4%);
  --ob-surface-sunken: color-mix(in srgb, var(--app-background), var(--app-text) 7%);
  --ob-heading: var(--app-heading);
  --ob-text: var(--app-text);
  --ob-text-muted: var(--app-text-muted);
  --ob-text-subtle: var(--app-text-subtle);
  --ob-border: var(--app-border);
  --ob-border-strong: var(--app-border-strong);
  --ob-accent: var(--app-accent);
  --ob-accent-hover: var(--app-accent-hover);
  --ob-accent-soft: color-mix(in srgb, var(--app-background), var(--app-accent) 12%);
  --ob-accent-contrast: var(--app-on-accent);
}
```

These selectors match the specificity of the preset's explicit and system-mode rules; loading them after the preset keeps aliases in effect in every mode. A plain `:root[data-ob-theme]` color override can lose to the dark preset rules. Map the secondary accent, code, notice, and alert tokens too when they should use host colors; the [complete token table]({% link themes.md %}#color-tokens) identifies each role. Keep Signal's font and shape tokens if that is the desired design.

Use opaque surface colors for cards and code blocks when translucent host tokens would expose unwanted layers beneath them. If the host has one continuous background behind header, reader, and footer, an optional **host-scoped** rule can make only that reader wrapper transparent (for example, `.site-atmosphere > .ob-page { background: transparent; }`).

Doctor checks contrast for `config.theme_colors`, not CSS-variable aliases. Inspect actual computed colors and contrast in the browser. Server-rendered `theme-color` tags also use configured preset colors, not arbitrary CSS overrides; if browser chrome must match before JavaScript, supply matching surface values in configuration or adapt that metadata in the host.

## Use one shared theme control

The theme control is a Stimulus button, not a separate navigation system. The standalone header supplies it; a custom layout can put a host-styled button in the shared navbar and omit the standalone header.

The existing controller contract is:

- Identifier `open-blog--theme`, action `open-blog--theme#cycle`.
- String values `systemLabel`, `lightLabel`, and `darkLabel`, with an optional `label` target for visible or screen-reader text.
- Preference key `localStorage["open-blog-theme"]`; Light and Dark set `data-theme` on `<html>`, while System removes both the saved preference and the attribute and follows the OS.
- The button starts `hidden`; the controller reveals it when connected. Preserve a useful accessible label and focus style when replacing its markup.

For a host-styled button, adapt this partial and give `site-theme-toggle` the application's button styling:

```erb
<% if OpenBlog.config.color_scheme.to_sym == :system %>
  <button type="button" class="site-theme-toggle" hidden
    data-controller="open-blog--theme" data-action="open-blog--theme#cycle"
    data-open-blog--theme-system-label-value="Theme: System"
    data-open-blog--theme-light-label-value="Theme: Light"
    data-open-blog--theme-dark-label-value="Theme: Dark">
    <span data-open-blog--theme-target="label">Theme: System</span>
  </button>
<% end %>
```

Use the host's translations in a localized application. For an icon-only version, retain the label target as visually hidden text and provide a comfortable target (the pilot used 44px). Render it once in the navbar, including at mobile widths.

Both homepage and blog must restore the same preference before styles load. The gem's `open_blog_theme_script` handles reader requests. If the host layout does not have the gem's helpers, extract equivalent restoration into a shared partial and render it in both layouts:

```erb
<% if OpenBlog.config.color_scheme.to_sym == :system %>
  <%= javascript_tag nonce: content_security_policy_nonce do %>
    (() => {
      try {
        const theme = localStorage.getItem("open-blog-theme");
        if (theme === "light" || theme === "dark") document.documentElement.dataset.theme = theme;
      } catch (_) {}
    })();
  <% end %>
<% end %>
```

Use one restoration script per page. With a fixed `config.color_scheme`, preserve the configured root attribute and omit the reader toggle. If the host already has a theme controller, choose one preference owner and adapt the other to it; two independent storage keys or competing controllers cause inconsistent navigation. Check Turbo navigation as well as full reloads if the host uses Turbo.

## Upgrade without losing host customizations

1. Read the target release's changelog, update the Gemfile constraint if pinned, and run `bundle update open_blog --conservative`. Review transitive dependency changes. Open Blog accepts JSON 2 and 3, but Rails 8.0 does not work with JSON 3; on Rails 8.0, keep `gem "json", "< 3"` in the Gemfile.
2. Locate the installed source with `bundle show open_blog`. The package is the authority for the version you are integrating.
3. Run `bin/rails generate open_blog:views` and review conflicts. It refreshes reader templates and the generated `layouts/open_blog.html.erb`; it does **not** refresh controllers, locale files, or theme sources. Use `--force` only for files you have reviewed and intend to replace.
4. Compare copied controllers with `app/assets/javascripts/open_blog/controllers/` in the gem, locales with `config/locales/open_blog.en.yml`, and theme sources with `lib/generators/open_blog/install/templates/theme/`. Merge needed changes, keeping host overrides. A normal installer rerun keeps conflicting files in a noninteractive terminal; it does not prove they are current. Avoid a blanket `open_blog:install --force`, which can overwrite the configured initializer too.
5. Review the host-owned blog layout against the updated generated layout for new helpers/assets. The generator leaves your differently named layout alone. For 0.1.0 to 0.2.0, replace old copied full-palette definitions with intentional overrides so they do not mask the preset; see the [theme upgrade guide]({% link themes.md %}#upgrade-from-010).
6. Copy new migrations with `bin/rails railties:install:migrations FROM=open_blog`, apply them to the intended database, rebuild host assets when needed, restart the application, and run the checks below. For 0.2.0 to 0.3.0 this copies `AlignOpenBlogRecordKeys`; see [image compatibility](#image-compatibility-is-a-separate-check).

## Verify the integration

Run `bin/rails open_blog:doctor`, relevant host tests, and real reader/API requests. Cover these independent outcomes:

- Homepage, blog index, article, and signed preview render; host logo/download/sign-in links still reach the intended host routes.
- One shared navbar/footer and theme control; one title, viewport, canonical, and main landmark; reader notices and structured data remain present.
- Explicit Light, explicit Dark, and System work on homepage and blog, persist across navigation/reload, and fit desktop and mobile without horizontal overflow. Confirm loaded fonts, computed colors, keyboard focus, and contrast.
- An authenticated draft can be saved and previewed; unauthenticated reads cannot expose it. Exercise publication and edits only in an authorized test/local context, including rejection of a public edit without a change type.
- A real image upload attaches successfully, its original URL works, and the card and avatar variant URLs under `/blog/media/` return images. Check the existing application's attachment behavior too.
- Feeds and sitemap respond; any promised scheduling is exercised with the actual worker or recurring task. Calling a job directly verifies its code, not the worker's operation.

Doctor compares record key types, but it does not upload an image. A text-only demo does not establish image compatibility or visual consistency. Report remaining failures separately from successful reader customization. These steps describe integration; they do not imply a production deployment or publication request.
