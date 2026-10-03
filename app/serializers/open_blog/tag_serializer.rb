module OpenBlog
  class TagSerializer
    def self.call(record)
      { id: record.id, name: record.name, slug: record.slug, posts_count: record.posts.count }
    end
  end
end
