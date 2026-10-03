---
name: open-blog-install
description: Install and configure Open Blog in a Rails host, customize its reader theme, and check setup.
---

Install the gem in the requested Rails application, then run `bin/rails generate open_blog:install`. Inspect the host's JavaScript, Tailwind, image processor, mount path, and authentication setup before selecting options. Use `--skip-tailwind` when the host should keep its CSS configuration; use the generated theme override for branding.

Run `bin/rails open_blog:doctor` or `blog_doctor` and resolve relevant errors. Configure the actual publisher, author, public base URL, and policy links. Replace placeholders with user-supplied identities. Keep the initial API token secret; installation prints it once and repeat runs do not recover it. A host authentication hook takes precedence over tokens.

Check `tools/list` before using MCP tools. Finish with an actual reader request and authenticated `blog_list_posts` call. Do not publish unrelated content, change production routing, or deploy merely because installation was requested.
