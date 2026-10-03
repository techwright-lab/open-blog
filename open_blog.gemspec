require_relative "lib/open_blog/version"

Gem::Specification.new do |spec|
  spec.name = "open_blog"
  spec.version = OpenBlog::VERSION
  spec.authors = [ "TechWright Labs" ]
  spec.email = [ "engineering@techwright.io" ]
  spec.summary = "An agentic blog engine for Rails."
  spec.description = "A Rails blog engine with reader pages, revision history, and agent publishing interfaces."
  spec.homepage = "https://github.com/techwright-lab/open-blog"
  spec.license = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 3.2", "< 4.1")

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["documentation_uri"] = "https://techwright-lab.github.io/open-blog/"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir[
    "lib/**/*", "app/**/*", "config/**/*", "db/**/*", "skills/**/*",
    "LICENSE.txt", "README.md", "CHANGELOG.md"
  ].select { |path| File.file?(path) }
  spec.require_paths = [ "lib" ]

  # Rails 8.0 passes quirks_mode, which JSON 3 no longer accepts.
  spec.add_dependency "json", ">= 2.3", "< 3"
  spec.add_dependency "rails", ">= 8.0", "< 9.0"
  spec.add_dependency "commonmarker", ">= 2.8", "< 3"
  spec.add_dependency "rouge", ">= 4.7", "< 6"
  spec.add_dependency "mcp", ">= 1.6", "< 2"

  spec.add_development_dependency "tailwindcss-ruby", "4.3.3"
  spec.add_development_dependency "pg", "~> 1.6"
  spec.add_development_dependency "sqlite3", "~> 2.1"
  spec.add_development_dependency "rubocop-rails-omakase", "~> 1.1"
  spec.add_development_dependency "capybara", "~> 3.40"
  spec.add_development_dependency "selenium-webdriver", "~> 4.0"
  spec.add_development_dependency "minitest", "~> 5.25"
  spec.add_development_dependency "rake", "~> 13.0"
end
