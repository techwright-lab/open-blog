module OpenBlog
  module ReaderDates
    def self.visible(time, now: Time.current)
      time if time && time <= now
    end

    def self.published_at(post, now: Time.current)
      visible(post.published_at, now: now)
    end

    def self.modified_at(post, now: Time.current)
      visible(post.modified_at, now: now)
    end

    def self.feed_updated_at(post, now: Time.current)
      modified_at(post, now: now) ||
        post.publications.where(entry_type: %w[first substantive correction adopted]).where("occurred_at <= ?", now).maximum(:occurred_at) ||
        visible(post.created_at, now: now) || now
    end
  end
end
