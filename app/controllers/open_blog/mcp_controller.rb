require "uri"

module OpenBlog
  class McpController < Api::V1::BaseController
    prepend_before_action :check_transport!

    def create
      server = ::MCP::Server.new(name: "open_blog", tools: Mcp.tools,
        server_context: { actor: actor, base_url: request.base_url })
      result = server.handle_json(request.raw_post)
      result.nil? ? head(:accepted) : render(body: result, content_type: "application/json")
    end

    private

    def check_transport!
      prevent_caching!
      raise Error::NotFound unless OpenBlog.config.mcp.enabled
      unless request.post?
        response.headers["Allow"] = "POST"
        return head :method_not_allowed
      end
      return unless request.headers.key?("Origin")
      origin = normalized_origin(request.headers["Origin"])
      allowed = [ request.base_url, OpenBlog.config.public_base_url ].compact.map { |value| normalized_origin(value) }
      raise Error::ScopeRequired.new(details: [ "origin" ]) unless origin && allowed.include?(origin)
    end

    def normalized_origin(value)
      uri = URI.parse(value.to_s)
      return unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil? &&
        uri.query.nil? && uri.fragment.nil? && [ "", "/" ].include?(uri.path)
      [ uri.scheme.downcase, uri.host.downcase, uri.port ]
    rescue URI::InvalidURIError
      nil
    end
  end
end
