module OpenBlog
  class Page < ApplicationRecord
    DEFAULT_SLUGS = { "responsible_party" => "responsible-party", "corrections" => "corrections",
      "editorial" => "editorial-policy", "ai_use" => "ai-use" }.freeze
    KINDS = DEFAULT_SLUGS.keys.freeze

    enum :status, { draft: "draft", published: "published" }, validate: true
    before_validation { self.slug = DEFAULT_SLUGS[kind] if slug.blank? }
    validates :kind, inclusion: { in: KINDS }, uniqueness: true
    validates :title, :slug, presence: true
    validates :slug, uniqueness: true, format: { with: /\A[a-z0-9]+(?:[-_][a-z0-9]+)*\z/ }
    validates :body_markdown, presence: true, if: :published?

    def path
      "#{OpenBlog.mount_path.chomp('/')}/policies/#{slug}"
    end

    def url(base: nil)
      origin = base || OpenBlog.config.public_base_url
      "#{origin.chomp('/')}#{path}" if origin
    end
  end
end
