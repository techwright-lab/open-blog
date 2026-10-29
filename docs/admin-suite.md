---
layout: default
title: AdminSuite
nav_order: 11
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

## API tokens

AdminSuite also manages API tokens at `<admin mount>/open_blog/api_tokens`. The generator writes `config/initializers/open_blog_api_tokens.rb` and `config/open_blog.yml`. Tokens stay disabled until the host supplies a trusted identity and a grant for it.

Set `config.api_tokens.identity` to a callable that receives the admin controller and returns a namespaced identity such as `"admin:42"`, or `nil` for no access. Bind it to the admin surface session, not to an application login fallback. The format is `namespace:id`, with a lowercase namespace and no whitespace.

```ruby
config.api_tokens.identity = ->(controller) { admin = controller.send(:current_admin); "admin:#{admin.uid}" if admin }
```

Grant access in `config/open_blog.yml`, keyed by identity. A missing file, or an identity with no entry, grants nothing. Use another policy object by setting `config.api_tokens.policy` to anything that responds to `grants_for(identity)`.

```yaml
api_tokens:
  grants:
    "admin:42":
      manage: [own, all]
      scopes: [read, write, publish]
```

| Grant | Allows |
| --- | --- |
| `manage: [own]` | List, issue, revoke, and rotate the identity's own tokens. |
| `manage: [all]` | List and revoke every token, including ones other identities issued and ones with no owner. Rotation stays limited to the identity's own tokens, so combine it with `own`. |
| `scopes` | Scopes the identity may put on a token: `read`, `write`, `publish`. No scope includes another. |

Without `all`, a request for another identity's token returns not found. A token with no owner, such as one from `open_blog:install_token`, cannot be rotated.

Each token has a name, at least one scope, and an expiry. The expiry defaults to `default_lifetime`. With `require_expiry` or `max_lifetime` set, the page does not offer no expiry. A token stops working at its expiry time. The expiry field and every time on these pages use the application time zone (`Time.zone`), and the pages name that zone.

Rotation issues a replacement with the same name and scopes and requires a confirm checkbox. The grace period is no grace, 1 hour, or 24 hours, limited by `max_grace`. With no grace, the old token is revoked at once; otherwise it keeps working until the grace period ends, or until its own earlier expiry. The page that shows the replacement states when the previous token stops working. A token can be rotated once.

The secret appears once, in the response to the issue or rotate form. It is sent with `Cache-Control: no-store`, is not in any URL, flash, or log, and cannot be shown again after a reload. Store it immediately. Events for issue, rotation, and revocation are recorded without secrets.

When `config.authenticate` is set, the API ignores tokens. The page then says tokens are inactive and refuses to issue or rotate; listing and revoking stay available. `bin/rails open_blog:doctor` reports whether token management is wired and names what is missing: the identity hook, the grant policy, grants in `config/open_blog.yml`, or tokens inactive because `config.authenticate` is set.
