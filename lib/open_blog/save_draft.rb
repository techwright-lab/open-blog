module OpenBlog
  class SaveDraft
    def self.call(attributes, post: nil, actor:, now: Time.current, authorize: nil)
      WritePost.call(attributes, post: post, actor: actor, now: now, publish: false, authorize: authorize)
    end
  end
end
