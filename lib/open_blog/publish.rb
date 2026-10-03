module OpenBlog
  class Publish
    def self.call(attributes, post: nil, actor:, now: Time.current)
      WritePost.call(attributes, post: post, actor: actor, now: now, publish: true)
    end
  end
end
