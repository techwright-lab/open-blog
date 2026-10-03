module OpenBlog
  class PostIdentity
    def self.resolve(attributes, post: nil)
      raise Error::ValidationFailed.new(details: [ "attributes" ]) unless attributes.is_a?(Hash)
      attributes = attributes.symbolize_keys
      %i[external_id slug].each do |field|
        if attributes.key?(field) && !attributes[field].nil? && !attributes[field].is_a?(String)
          raise Error::ValidationFailed.new(details: [ field.to_s ])
        end
      end
      unless post
        external = Post.find_by(external_id: attributes[:external_id]) if attributes[:external_id].present?
        slug = Post.find_by(slug: attributes[:slug]) if attributes[:slug].present?
        raise Error::IdentityConflict if external && slug && external != slug
        post = external || slug || Post.new
      end
      candidate = attributes[:slug].presence || post.slug
      if candidate.present?
        reserved = Post::RESERVED_SLUGS + OpenBlog.config.route_segments.values
        redirect = Redirect.find_by(old_path: "#{OpenBlog.mount_path.chomp('/')}/#{candidate}")
        if reserved.include?(candidate) || (redirect && (post.new_record? || redirect.post_id != post.id))
          raise Error::SlugReserved
        end
      end
      post
    end
  end
end
