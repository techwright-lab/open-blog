---
layout: default
title: Working on the docs
nav_order: 14
permalink: /contributing/
---

# Working on the docs

Edit the Markdown files in `docs/`. Each page has YAML front matter for its title, navigation order, and URL. Public guides describe the gem's supported behavior and should include runnable examples.

The site uses Jekyll and Just the Docs. Its Gemfile and lockfile are separate from the Rails gem's bundle. From the repository root, with Ruby 3.4 available:

```sh
BUNDLE_GEMFILE=docs/Gemfile bundle install
BUNDLE_GEMFILE=docs/Gemfile bundle exec jekyll serve --source docs --destination docs/_site --host 127.0.0.1
```

Open <http://127.0.0.1:4000/open-blog/>. Keep the `/open-blog/` prefix when checking links locally; GitHub Pages uses the same prefix.

Before opening a pull request, build and check the site:

```sh
BUNDLE_GEMFILE=docs/Gemfile bundle exec jekyll build --source docs --destination docs/_site --strict_front_matter
BUNDLE_GEMFILE=docs/Gemfile bundle exec ruby bin/check-docs docs/_site
```

The **Docs** workflow runs for pull requests, pushes to `main`, and manual dispatches. It validates the rendered site before deployment. Deployment runs only from the upstream repository's `main` branch. A release preparation branch can run these checks without publishing the site.

Keep assets inside `docs/assets/` and use Jekyll's `relative_url` filter for links to site pages or assets. The deployed artifact is built from `docs/`; it does not include the rest of the source checkout. Documentation dependencies and generated site files are excluded from the RubyGem.

The changelog remains in the repository's `CHANGELOG.md`. Add user-facing changes under **Unreleased** as part of each feature or fix. The [release workflow]({{ '/releases/' | relative_url }}) moves those notes into a dated release entry.
