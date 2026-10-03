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
      RedirectTarget.synchronize do
        target = RedirectTarget.call(target, from: post.path)
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
    end

    def self.retained_records?(post)
      post.public_revision_id.present? || post.revisions.exists? || post.publications.exists? ||
        post.approvals.exists? || post.connection_declarations.exists? || post.baseline.present? ||
        Redirect.where(post_id: post.id).exists?
    end
    private_class_method :retained_records?
  end
end
