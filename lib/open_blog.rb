require "json"
require "rails"
require "commonmarker"
require "rouge"
require "mcp"

require_relative "open_blog/version"

module OpenBlog
  autoload :Configuration, "open_blog/configuration"
  autoload :ConfigurationError, "open_blog/configuration_error"
  autoload :RevisionPayload, "open_blog/revision_payload"
  autoload :PlainText, "open_blog/plain_text"

  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield config
      config
    end

    def mount_path
      application = Rails.application
      return config.mount_path unless application&.initialized?

      route = application.routes.routes.find do |candidate|
        candidate.app.respond_to?(:app) && candidate.app.app == Engine
      end
      route ? route.path.spec.to_s : config.mount_path
    end
  end
end

require_relative "open_blog/engine"
