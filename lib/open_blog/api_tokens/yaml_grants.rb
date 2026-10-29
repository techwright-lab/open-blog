require "yaml"
require "open_blog/configuration_error"
require "open_blog/api_tokens/grant"

module OpenBlog
  module ApiTokens
    class YamlGrants
      MANAGE_LEVELS = %w[own all].freeze

      def self.load(path)
        return new({}) unless File.exist?(path)

        document = YAML.safe_load_file(path)
        new(parse(document, path))
      rescue Psych::Exception => error
        raise ConfigurationError, "OpenBlog api_tokens grants #{path} is not valid YAML: #{error.message}"
      end

      def self.parse(document, path)
        return {} if document.nil?
        fail_with(path, "must be a mapping") unless document.is_a?(Hash)
        unknown = document.keys - [ "api_tokens" ]
        fail_with(path, "has unknown top-level keys: #{unknown.join(', ')}") if unknown.any?
        section = document["api_tokens"]
        return {} if section.nil?
        fail_with(path, "api_tokens must be a mapping") unless section.is_a?(Hash)
        unknown = section.keys - [ "grants" ]
        fail_with(path, "api_tokens has unknown keys: #{unknown.join(', ')}") if unknown.any?
        grants = section["grants"]
        return {} if grants.nil?
        fail_with(path, "grants must be a mapping") unless grants.is_a?(Hash)
        grants.to_h { |identity, grant| [ identity, build_grant(identity, grant, path) ] }
      end
      private_class_method :parse

      def self.build_grant(identity, grant, path)
        fail_with(path, "grant key #{identity.inspect} must match #{IDENTITY.source}") unless identity.is_a?(String) && identity.match?(IDENTITY)
        fail_with(path, "grant #{identity} must be a mapping") unless grant.is_a?(Hash)
        unknown = grant.keys - %w[manage scopes]
        fail_with(path, "grant #{identity} has unknown keys: #{unknown.join(', ')}") if unknown.any?
        manage = Array(grant["manage"]).map(&:to_s)
        fail_with(path, "grant #{identity} manage must be own or all") unless (manage - MANAGE_LEVELS).empty?
        scopes = Array(grant["scopes"]).map(&:to_s)
        fail_with(path, "grant #{identity} scopes must be within #{SCOPES.join(', ')}") unless (scopes - SCOPES).empty?
        Grant.new(manage_own: manage.include?("own"), manage_all: manage.include?("all"), scopes: scopes.uniq)
      end
      private_class_method :build_grant

      def self.fail_with(path, message)
        raise ConfigurationError, "OpenBlog api_tokens grants #{path} #{message}"
      end
      private_class_method :fail_with

      def initialize(grants)
        @grants = grants.freeze
      end

      def grants_for(identity)
        @grants[identity]
      end

      def empty?
        @grants.empty?
      end
    end
  end
end
