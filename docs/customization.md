---
layout: default
title: Customization
nav_order: 8
permalink: /customization/
---

# Customization

The installer copies the reader templates into the host's `app/views/open_blog` and the layout to `app/views/layouts/open_blog.html.erb`. They call gem helpers for metadata, structured data, dates, and notices, so you can change markup freely and keep the published data intact. Refresh them after an upgrade:

```sh
bin/rails generate open_blog:views
```

Changed files are kept unless you pass `--force`; review the diff and accept replacements deliberately.

## Themes and stylesheets

The look of the reader comes from a preset that you select with `config.theme`. The [themes guide]({% link themes.md %}) covers the presets, palette overrides with `config.theme_colors`, the token reference, and fonts. Do not edit token values in the copied files; set them in the configuration or in the override file that the guide names.

Each preset has a light and a dark mode. `config.color_scheme` defaults to `:system`; readers can select light or dark, and their choice is saved locally in the browser. Set it to `:light` or `:dark` to fix the mode. Without JavaScript, pages remain readable and the system mode still applies.

```ruby
config.color_scheme = :dark
config.syntax_theme = "gruvbox"
config.call_to_action = { title: "Newsletter", text: "One letter a month.", label: "Subscribe", url: "https://example.com/newsletter" }
```

The gem serves the preset stylesheet `open_blog/themes.css` in every host setup. With Tailwind 4, the copied component styles live in `app/assets/tailwind/open_blog`, and the blog layout loads the preset with `open_blog_theme_stylesheets` and then your host build. With `--skip-tailwind` or Tailwind 3, `open_blog_stylesheets` loads the preset, the gem's compiled stylesheet, and then `app/assets/stylesheets/open_blog_theme.css`. The compiled stylesheets stay in the gem. Maintainers rebuild them with `bin/rails open_blog:build_css`; `OUT=/tmp/blog.css` selects another output path.

Generate syntax colors for the configured theme with `bin/rails open_blog:syntax_css`. The output includes light, explicit dark, and system dark rules scoped to code blocks. `config.syntax_theme` defaults to `"github"`; `"base16"` and `"gruvbox"` also support both modes.

## Browser controllers

The installer copies browser controllers to `app/javascript/controllers/open_blog` and registers them with the `open-blog--` prefix. They enable the theme toggle, link and code copying, device sharing, table-of-contents tracking, and reading progress. If you change the blog layout to load a separate JavaScript entry point, register these controllers there too.

## Rendering

Render stored content with `OpenBlog::Renderer.render(post)`, or preview a string with `OpenBlog::Renderer.render_string(text, format: :markdown)`. Both return sanitized HTML with heading links, syntax highlighting, image figures, and table wrappers.

```ruby
OpenBlog::Renderer.render_string("## Heading\n\nSome `code` here.", format: :markdown)
# => <h2 id="heading">Heading<a class="ob-heading-anchor" href="#heading" aria-label="Link to Heading">#</a></h2>
#    <p>Some <code>code</code> here.</p>
```

Markdown also supports task lists, footnotes, and alerts. Rich-text input cannot supply its own classes, IDs, styles, or event handlers. Rendering does not write records or fetch image bytes.
