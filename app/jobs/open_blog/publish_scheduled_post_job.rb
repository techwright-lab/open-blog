module OpenBlog
  class PublishScheduledPostJob < ActiveJob::Base
    def perform(post_id)
      Post.transaction do
        post = Post.lock.find_by(id: post_id)
        now = Time.current
        next unless post&.scheduled? && post.publish_at && post.publish_at <= now
        result = WritePost.call({}, post: post, actor: nil, now: now, publish: :scheduled)
        raise result.error unless result.success?
        result
      end
    end
  end
end
