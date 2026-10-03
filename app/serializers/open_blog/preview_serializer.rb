module OpenBlog
  class PreviewSerializer
    def self.call(post, base_url: nil)
      credentials = post.preview_credentials
      origin = OpenBlog.config.public_base_url || base_url
      path = "#{OpenBlog.mount_path.chomp('/')}/preview/#{ERB::Util.url_encode(credentials.fetch(:token))}"
      { preview_url: "#{origin.to_s.chomp('/')}#{path}", revision_identifier: post.current_revision_identifier,
        expires_at: credentials.fetch(:expires_at).iso8601 }
    end
  end
end
