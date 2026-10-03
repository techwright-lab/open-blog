require "stringio"
require "uri"

module OpenBlog
  module Mcp
    class Dispatcher
      CONTROLLERS = %w[posts approvals connections records findings doctor images categories tags authors series redirects adoptions faq_extractions previews pages].freeze
      METHODS = %w[GET POST PUT PATCH DELETE].freeze

      def self.call(controller:, action:, method:, arguments:, actor:, route_params: {}, base_url: nil)
        raise ArgumentError, "Unknown publishing controller" unless CONTROLLERS.include?(controller.to_s)
        verb = method.to_s.upcase
        raise ArgumentError, "Unsupported request method" unless METHODS.include?(verb)
        klass = "OpenBlog::Api::V1::#{controller.to_s.camelize}Controller".constantize
        raise ArgumentError, "Unknown publishing action" unless klass.action_methods.include?(action.to_s)
        origin = URI.parse(OpenBlog.config.public_base_url || base_url || "http://localhost")
        env = { "REQUEST_METHOD" => verb, "SCRIPT_NAME" => "", "PATH_INFO" => "#{OpenBlog.mount_path}/api/v1/#{controller}",
          "QUERY_STRING" => "", "SERVER_NAME" => origin.host, "SERVER_PORT" => origin.port.to_s,
          "rack.url_scheme" => origin.scheme, "rack.input" => StringIO.new(""), "CONTENT_TYPE" => "application/json",
          "action_dispatch.request.request_parameters" => arguments.deep_stringify_keys,
          "action_dispatch.request.path_parameters" => route_params.symbolize_keys.merge(controller: klass.controller_path, action: action.to_s) }
        request = ActionDispatch::Request.new(env)
        response = ActionDispatch::Response.new
        _status, _headers, body = klass.new.send(:dispatch_internal, action.to_s, request, response, actor: actor)
        text = +""
        body.each { |chunk| text << chunk }
        text.empty? ? {} : JSON.parse(text)
      ensure
        body&.close if body.respond_to?(:close)
      end
    end
  end
end
