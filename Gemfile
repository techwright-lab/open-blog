source "https://rubygems.org"

gem "rails", ENV.fetch("RAILS_VERSION", ">= 8.0, < 9.0").split(",").map(&:strip)
gem "json", ENV.fetch("JSON_VERSION").split(",").map(&:strip) if ENV.key?("JSON_VERSION")
gem "propshaft"
gem "importmap-rails"
gem "stimulus-rails", "~> 1.3"
gem "puma", ">= 6.0", "< 9"
gem "tailwindcss-rails", "~> 4.0"
gem "image_processing"
gem "mini_magick", ">= 4.13", "< 6"

gemspec
