require "uri"

module OpenBlog
  class Post < ApplicationRecord
    RESERVED_SLUGS = %w[feed search preview media policies api mcp sitemap].freeze
    SLUG_PATTERN = /\A[a-z0-9]+(?:[-_][a-z0-9]+)*\z/

    belongs_to :author
    belongs_to :category, optional: true
    belongs_to :series, optional: true
    belongs_to :cover_image, class_name: "OpenBlog::Image", optional: true
    belongs_to :social_image, class_name: "OpenBlog::Image", optional: true
    belongs_to :public_revision, class_name: "OpenBlog::Revision", optional: true

    has_many :faqs, -> { order(:position) }, autosave: true, dependent: :destroy, inverse_of: :post
    has_many :taggings, autosave: true, dependent: :destroy
    has_many :tags, through: :taggings, autosave: false
    has_many :revisions, dependent: :restrict_with_exception
    has_many :approvals, dependent: :restrict_with_exception
    has_many :publications, dependent: :restrict_with_exception
    has_many :connection_declarations, dependent: :restrict_with_exception
    has_one :baseline, dependent: :restrict_with_exception
    has_rich_text :rich_body

    attribute :body_format, :string, default: -> { OpenBlog.config.default_body_format.to_s }
    enum :body_format, { markdown: "markdown", rich_text: "rich_text" }, validate: true
    enum :status, { draft: "draft", scheduled: "scheduled", published: "published", archived: "archived" }, validate: true
    enum :provenance, { ai_assisted: "ai_assisted", human_written: "human_written", unknown: "unknown" }, validate: true, prefix: true

    validates :title, :author_name, presence: true
    validates :slug, presence: true, uniqueness: true, format: { with: SLUG_PATTERN }
    validates :external_id, uniqueness: true, allow_nil: true
    validates :canonical_url, length: { maximum: 2048 }, allow_nil: true
    validates :body_format, inclusion: { in: ->(_post) { OpenBlog.config.body_formats.map(&:to_s) } }
    validates :series_position, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
    validates :series_position, uniqueness: { scope: :series_id }, if: -> { series_id && series_position }
    validate :slug_is_available
    validate :public_revision_ownership
    validate :canonical_url_is_absolute

    scope :listed, -> { where(status: "published") }

    attr_accessor :release_context, :release_records

    before_save :compute_derived
    after_save :record_release
    around_save :guard_parent_content, prepend: true
    around_destroy :guard_parent_content, prepend: true

    def path
      "#{OpenBlog.mount_path.chomp('/')}/#{slug}"
    end

    def url(base: nil)
      origin = base || OpenBlog.config.public_base_url
      "#{origin.chomp('/')}#{path}" if origin
    end

    def faq_list
      faqs.to_a.reject(&:marked_for_destruction?).sort_by { |entry| entry.position || 0 }.map do |entry|
        { question: entry.question, answer: entry.answer }
      end
    end

    def body_for_payload
      return body_markdown.to_s if markdown?

      if rich_body.will_save_change_to_body?
        rich_body.read_attribute_for_database(:body).to_s
      else
        rich_body.read_attribute_before_type_cast(:body).to_s
      end
    end

    private

    def guard_parent_content(&block)
      ContentGuard.with_parent(self, &block)
    end

    def record_release
      republishing = saved_change_to_status? && status_before_last_save != "published"
      self.release_records = RecordRelease.call(self, **(release_context || {}), republishing: republishing)
    ensure
      self.release_context = nil
    end

    def canonical_url_is_absolute
      return if canonical_url.nil?

      uri = URI.parse(canonical_url)
      unless uri.is_a?(URI::HTTP) && uri.host.present?
        errors.add(:canonical_url, "must be an absolute HTTP or HTTPS URL")
      end
    rescue URI::InvalidURIError
      errors.add(:canonical_url, "must be an absolute HTTP or HTTPS URL")
    end

    def compute_derived
      self.current_revision_identifier = RevisionPayload.new(self).identifier
      body_text = markdown? ? PlainText.from_markdown(body_markdown) : PlainText.from_html(body_for_payload)
      faq_text = faq_list.flat_map { |entry| entry.values_at(:question, :answer) }.join("\n")
      self.word_count = [ body_text, faq_text ].join("\n").split.length
      self.reading_time_minutes = [ (word_count / 238.0).ceil, 1 ].max
      self.search_text = [ title, description, body_text, faq_text ].join("\n")
    end

    def slug_is_available
      if (RESERVED_SLUGS + OpenBlog.config.route_segments.values).include?(slug)
        errors.add(:slug, "is reserved")
      end
      redirect = Redirect.find_by(old_path: path)
      if redirect && (new_record? || redirect.post_id != id)
        errors.add(:slug, "belongs to an existing redirect")
      end
    end

    def public_revision_ownership
      if public_revision && (new_record? || public_revision.post_id != id)
        errors.add(:public_revision, "must belong to this post")
      end
    end
  end
end
