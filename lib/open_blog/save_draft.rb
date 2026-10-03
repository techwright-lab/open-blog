module OpenBlog
  class SaveDraft
    def self.call(attributes, post: nil, actor:, now: Time.current)
      WritePost.call(attributes, post: post, actor: actor, now: now, publish: false)
    end
  end
end
