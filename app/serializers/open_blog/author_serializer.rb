module OpenBlog
  class AuthorSerializer
    def self.call(record)
      image = ImageResolution.image_for_attachment(record.avatar.blob) if record.avatar.attached?
      { id: record.id, name: record.name, slug: record.slug, type: record.author_type, bio: record.bio,
        url: record.url, profile_urls: record.profile_urls, avatar: ImageSerializer.call(image),
        host_reference: record.host_reference, posts_count: record.posts.count }
    end
  end
end
