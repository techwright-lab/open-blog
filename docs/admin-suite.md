---
layout: default
title: AdminSuite
nav_order: 10
permalink: /admin-suite/
---

# AdminSuite

For an optional admin interface, add AdminSuite and generate its blog resources:

```sh
bundle add admin_suite --version "~> 0.6.1"
bin/rails generate open_blog:admin_suite
```

Configure AdminSuite authentication in the host and restart the application. The generator adds post, category, author, and policy-page resources, a blog portal, and its discovery initializer. `--dir=config/blog_admin` changes the definition directory; `open_blog:install --admin-suite` also runs this generator. Repeated runs preserve customized files unless forced.

The post form edits FAQ questions, answers, and positive unique positions in the same save as the article. It can add or remove entries; invalid entries roll back the whole save. Reordering into an occupied position requires an unused intermediate position. Public content edits record one revision and a substantive release with no claimed approval or named actor. Publishing history appears in read-only panels. Rich-text editing uses the host's Action Text editor setup; the form preserves the article's existing body format. Use the publishing API for body-format changes, scheduling, URL moves, removal records, and approval workflows.
