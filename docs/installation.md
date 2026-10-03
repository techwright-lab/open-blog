---
layout: default
title: Installation
nav_order: 2
permalink: /installation/
---

# Installation

Install into a Rails 8 application with libvips available for image processing (or ImageMagick if your host uses that backend):

```sh
bundle add open_blog --github techwright-lab/open-blog
bin/rails generate open_blog:install
```

Start the host with `bin/dev` (or `bin/rails server`) and open `/blog`. Set your site and author names in the generated initializer, or pass `--site-name="My Journal" --author-name="Example Author"` to the generator.

The generator installs the tables, mounts `/blog`, copies reader views and browser controllers, and publishes one sample article. When the host has no authentication hook or existing token, it prints one API token; save the secret because repeated installation will not show it again. It detects importmap or a JavaScript bundler and Tailwind 4. If Tailwind is absent, its installer also changes the host's application layout and development scripts. Use `--skip-tailwind` to keep the host's CSS setup and load the gem's compiled stylesheet only in the blog layout.

Options include `--mount-at=/journal`, `--mount-position=first`, `--body-format=markdown|rich_text|both`, `--skip-sample`, and `--skip-migrate`. The default mount position is last so existing host routes retain precedence. Repeating installation reuses the sample and migrations. `--skip-migrate` also defers the sample and token until you run the migrations. Then run `bin/rails open_blog:sample` and `bin/rails open_blog:install_token` as needed. Changed files are kept in a noninteractive terminal; use `--force` to replace them. `bin/rails generate open_blog:views` refreshes only the copied views.

## Configure your site

Run `bin/rails open_blog:doctor` to inspect configuration, assets, routes, storage, and publishing records. Errors return exit status 1; warnings identify setup still needed. Set your public origin and replace any placeholder identities in `config/initializers/open_blog.rb`:

```ruby
OpenBlog.configure do |config|
  config.site_name = "My Journal"
  config.public_base_url = "https://example.com"
  config.default_author = { name: "Example Author", type: :person }
  config.publisher = { name: "My Company", url: "https://example.com" }
end
```

Required configuration is checked at application boot. The copied templates live in the host's `app/views/open_blog` and call gem helpers for metadata, structured data, dates, and notices. Customize those views and `app/views/layouts/open_blog.html.erb` in your application.

See [configuration]({% link configuration.md %}) for runtime settings and [customization]({% link customization.md %}) for reader assets.
