module OpenBlog
  class Publish
    def self.call(attributes, post: nil, actor:, now: Time.current, authorize: nil)
      WritePost.call(attributes, post: post, actor: actor, now: now, publish: true, authorize: authorize)
    end
  end
end
