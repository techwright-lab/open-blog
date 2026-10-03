# Open Blog

A Rails blog engine with Markdown and rich-text articles, responsive reader pages, revision history, and publishing through Ruby, a JSON API, or MCP tools.

[Documentation](https://techwright-lab.github.io/open-blog/) · [API reference](https://techwright-lab.github.io/open-blog/api/) · [Changelog](CHANGELOG.md)

## Install

Use a Rails 8 application with PostgreSQL or SQLite and libvips available for image processing (or ImageMagick if your host uses that backend). Install from GitHub:

```sh
bundle add open_blog --github techwright-lab/open-blog
bin/rails generate open_blog:install
```

Start `bin/dev` (or `bin/rails server`) and open `/blog`. The generator installs tables, mounts the engine, copies customizable views and browser controllers, and publishes a sample article. Configure your site name, publisher, and public origin in `config/initializers/open_blog.rb`.

If the installer prints an API token, save it: the secret is shown once. Use `--skip-tailwind` to load the gem's compiled stylesheet without changing the host's CSS setup. See the [installation guide](https://techwright-lab.github.io/open-blog/installation/) for all options.

![Default blog in the light theme](.github/images/reader-light.png)

![Default blog in the dark theme](.github/images/reader-dark.png)

## Use

- [Configuration](https://techwright-lab.github.io/open-blog/configuration/): identity, authentication, storage, and host integration.
- [Publishing](https://techwright-lab.github.io/open-blog/publishing/): drafts, previews, approvals, scheduling, and recorded changes.
- [JSON API](https://techwright-lab.github.io/open-blog/api/) and [MCP](https://techwright-lab.github.io/open-blog/mcp/): authenticated tools for editorial work.
- [Adoption](https://techwright-lab.github.io/open-blog/adoption/): import existing articles and preserve their known history.
- [Customization](https://techwright-lab.github.io/open-blog/customization/): copied templates, themes, and browser controllers.
- [AdminSuite](https://techwright-lab.github.io/open-blog/admin-suite/): optional administrative forms and read-only history.

Show users the exact content before recording their approval; never invent an approval or fact-check. Packaged agent workflows are available under `OpenBlog::Engine.root.join("skills")`. Normal model saves and publishing operations retain revision history; bulk SQL writes bypass auditing.

## Documentation and releases

The documentation is Markdown in `docs/`, built with Jekyll and Just the Docs. Its separate bundle keeps site dependencies out of the gem. See [working on the documentation](https://techwright-lab.github.io/open-blog/contributing/) for local preview and validation commands.

The **Prepare Release** workflow updates the version and changelog in a pull request. After review, merge, and successful checks, **Publish** publishes the verified package to RubyGems and creates or updates the corresponding GitHub Release. See the [release guide](https://techwright-lab.github.io/open-blog/releases/) for initial Trusted Publishing setup and the exact steps. Merging ordinary changes does not publish a gem.

Licensed under the [MIT License](LICENSE.txt).
