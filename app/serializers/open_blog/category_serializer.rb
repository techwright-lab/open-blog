module OpenBlog
  class CategorySerializer
    def self.call(record)
      { id: record.id, name: record.name, slug: record.slug, description: record.description, position: record.position, posts_count: record.posts.count }
    end
  end
end
