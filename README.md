# Open Blog

An agentic blog engine for Rails. **Not released:** the gem currently provides a mountable engine and configuration. Publishing interfaces and reader pages are under development.

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

Licensed under the [MIT License](LICENSE.txt).
