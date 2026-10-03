module OpenBlog
  class SeriesSerializer
    def self.call(record)
      { id: record.id, name: record.name, slug: record.slug, description: record.description, posts: record.posts.order(:series_position, :id).map { |post| { id: post.id, slug: post.slug, title: post.title, position: post.series_position } } }
    end
  end
end
