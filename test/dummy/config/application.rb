require_relative "boot"
require "rails/all"
Bundler.require(*Rails.groups)

module Dummy
  class Application < Rails::Application
    config.load_defaults 8.0
    config.paths["db/migrate"] << OpenBlog::Engine.root.join("db/migrate").to_s
    config.paths["app/views"] << OpenBlog::Engine.root.join("lib/generators/open_blog/install/templates/views").to_s
    config.eager_load = false
    config.secret_key_base = "open-blog-dummy-test-secret-key-base" * 4
    config.active_record.dump_schema_after_migration = false
    config.active_storage.service = :local
    config.active_storage.variant_processor = :mini_magick
    config.active_job.queue_adapter = :test
    config.action_mailer.default_url_options = { host: "example.test" }
    config.hosts.clear
  end
end
