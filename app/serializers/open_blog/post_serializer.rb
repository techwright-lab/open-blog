module OpenBlog
  class PostSerializer
    def self.call(post, base_url: nil, card: false)
      new(post, base_url: base_url).call(card: card)
    end

    def initialize(post, base_url:)
      @post, @base_url = post, OpenBlog.config.public_base_url || base_url
    end

    def call(card: false)
      result = {
        id: @post.id, slug: @post.slug, url: @post.url(base: @base_url), status: @post.status,
        title: @post.title, description: @post.description, author: author,
        category: taxonomy(@post.category), tags: @post.tags.map(&:name),
        published_at: timestamp(@post.published_at), modified_at: timestamp(@post.modified_at),
        revision_identifier: @post.current_revision_identifier, label: LabelPolicy.for(@post).to_s
      }
      return result if card

      result.merge(search_title: @post.search_title, search_description: @post.search_description,
        body_format: @post.body_format, body: @post.body_for_payload,
        series: @post.series && taxonomy(@post.series).merge(position: @post.series_position),
        featured: @post.featured, canonical_url: @post.canonical_url,
        cover_image: ImageSerializer.call(@post.cover_image), cover_alt: @post.cover_alt,
        social_image: ImageSerializer.call(@post.social_image), faq: @post.faq_list,
        provenance: @post.provenance, provenance_evidence: @post.provenance_evidence,
        external_id: @post.external_id, publish_at: timestamp(@post.publish_at),
        public_revision_identifier: @post.public_revision&.identifier,
        approved: @post.public_revision_id.present? && @post.approvals.exists?(revision_id: @post.public_revision_id, facts_checked: true),
        preview_url: nil, reading_time_minutes: @post.reading_time_minutes, word_count: @post.word_count,
        created_at: timestamp(@post.created_at), updated_at: timestamp(@post.updated_at))
    end

    private

    def author
      record = @post.author
      { id: record.id, name: record.name, slug: record.slug, type: record.author_type, url: record.url }
    end

    def taxonomy(record)
      { id: record.id, name: record.name, slug: record.slug } if record
    end

    def timestamp(value)
      value&.iso8601
    end
  end
end
