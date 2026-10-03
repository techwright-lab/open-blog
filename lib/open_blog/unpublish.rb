module OpenBlog
  class Unpublish
    def self.call(post, actor:, now: Time.current)
      Operation.run(post: post, actor: actor, now: now) do |current, _created|
        raise Error::NotFound unless current.persisted?
        was_public = current.published?
        current.update!(status: "draft", publish_at: nil)
        Remove.write_redirect(current, target: nil, source: "unpublish", now: now) if was_public
        { revision: nil, publication: nil, approval: nil }
      end
    end
  end
end
