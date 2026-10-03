module OpenBlog
  module Authentication
    def self.actor_for(request)
      if (hook = OpenBlog.config.authenticate)
        source = hook.call(request)
        return unless source
        scopes = source.respond_to?(:scopes) ? source.scopes : ApiToken::SCOPES
        identity = source.respond_to?(:id) && source.id.present? ? source.id : source.name
        return Actor.new(name: source.name, scopes: scopes, id: "hook:#{identity}")
      end

      match = /\ABearer (ob_[1-9A-HJ-NP-Za-km-z]{40})\z/.match(request.authorization.to_s)
      return unless match
      token = ApiToken.authenticate(match[1])
      Actor.new(name: token.name, scopes: token.scopes, id: "token:#{token.id}") if token
    end
  end
end
