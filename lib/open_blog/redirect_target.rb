require "uri"

module OpenBlog
  class RedirectTarget
    LOCK_KEY = 1_867_541_239

    def self.synchronize
      Redirect.transaction do
        connection = Redirect.connection
        if connection.adapter_name == "PostgreSQL"
          connection.execute("SELECT pg_advisory_xact_lock(#{LOCK_KEY})")
        elsif connection.adapter_name == "SQLite"
          connection.execute("UPDATE open_blog_redirects SET id = id WHERE 1 = 0")
        end
        yield
      end
    rescue ActiveRecord::StatementInvalid => error
      raise unless error.cause.class.name == "SQLite3::BusyException"
      raise Error::ValidationFailed.new(details: [ "redirects" ])
    end

    def self.call(target, from:)
      visited = [ from ]
      while target
        target, path = normalize_target(target)
        raise Error::ValidationFailed.new(details: [ "redirect_to" ]) if visited.include?(path)
        visited << path
        redirect = Redirect.find_by(old_path: path)
        break unless redirect
        target = redirect.new_path
      end
      target
    end
    def self.normalize_target(target)
      unless target.is_a?(String) && target.present? && !target.match?(/\s/)
        raise Error::ValidationFailed.new(details: [ "redirect_to" ])
      end
      uri = URI.parse(target)
      if target.start_with?("/") && !target.start_with?("//") && !uri.host && !uri.scheme
        return [ target, uri.path ]
      end
      unless uri.is_a?(URI::HTTP) && uri.host.present? && !uri.userinfo
        raise Error::ValidationFailed.new(details: [ "redirect_to" ])
      end
      origin = URI.parse(OpenBlog.config.public_base_url) if OpenBlog.config.public_base_url
      if origin && [ origin.scheme, origin.host, origin.port ] == [ uri.scheme, uri.host, uri.port ]
        target = uri.request_uri
        target += "##{uri.fragment}" if uri.fragment
        [ target, uri.path ]
      else
        [ target, target ]
      end
    rescue URI::InvalidURIError
      raise Error::ValidationFailed.new(details: [ "redirect_to" ])
    end
    private_class_method :normalize_target
  end
end
