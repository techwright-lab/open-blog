require "uri"

module OpenBlog
  class Remove
    def self.call(post, redirect_to: nil, actor:, now: Time.current)
      Operation.run(post: post, actor: actor, now: now) do |current, _created|
        raise Error::NotFound unless current.persisted?
        if (current.draft? || current.scheduled?) && !retained_records?(current)
          current.destroy!
        else
          current.update!(status: "archived", publish_at: nil)
          write_redirect(current, target: redirect_to, source: "removal", now: now)
        end
        { revision: nil, publication: nil, approval: nil }
      end
    end

    def self.write_redirect(post, target:, source:, now:)
      target = resolve_target(target, from: post.path)
      redirect = Redirect.find_by(old_path: post.path)
      raise Error::SlugReserved if redirect && redirect.post_id != post.id

      if redirect
        redirect.update!(new_path: target)
      else
        Redirect.create!(old_path: post.path, new_path: target, source: source,
          post: post, occurred_on: now.to_date)
      end
      Redirect.where(new_path: post.path).where.not(old_path: post.path).find_each do |incoming|
        incoming.update!(new_path: target)
      end
    end

    def self.resolve_target(target, from:)
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
    private_class_method :resolve_target, :normalize_target

    def self.retained_records?(post)
      post.public_revision_id.present? || post.revisions.exists? || post.publications.exists? ||
        post.approvals.exists? || post.connection_declarations.exists? || post.baseline.present? ||
        Redirect.where(post_id: post.id).exists?
    end
    private_class_method :retained_records?
  end
end
