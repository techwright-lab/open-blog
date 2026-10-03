# Open Blog

An agentic blog engine for Rails. **Not released:** the gem currently provides a mountable engine, configuration, content models, and Ruby publishing operations for PostgreSQL and SQLite. HTTP interfaces and reader pages are under development.

Configure the engine in `config/initializers/open_blog.rb`:

```ruby
OpenBlog.configure do |config|
  config.site_name = "My Journal"
  config.public_base_url = "https://example.com"
  config.default_author = { name: "Example Author", type: :person }
  config.publisher = { name: "My Company", url: "https://example.com" }
end
```

Mount it in `config/routes.rb` with `mount OpenBlog::Engine => "/blog"`.
Required configuration is checked at application boot. The mounted engine currently returns 404 until reader routes are added.

Posts support Markdown or opt-in rich text, ordered FAQs, authors, categories, tags, and series. Revision identifiers are computed from normalized content; stored revisions, approvals, publication records, and images are immutable through the model APIs.

Publish from Ruby with `OpenBlog::Publish.call({ title: "Garden notes", body: "Today in the garden." }, actor: "Editor")`. Every operation returns a result with `success?`, `post`, `records`, and a typed `error` on refusal. Updates to public content require `change: "substantive"`, `"correction"` (with `note`), or `"maintenance"`. Drafts use `OpenBlog::SaveDraft.call`.

Future `publish_at` values store a schedule and enqueue a job after commit. Scheduled job execution, labels, and findings are still under development.

Licensed under the [MIT License](LICENSE.txt).
