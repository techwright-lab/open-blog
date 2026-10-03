module OpenBlog
  class RecordRelease
    def self.call(post, change: nil, note: nil, description: nil, actor: nil, now: Time.current, made_by_ai: nil, republishing: false)
      post.class.transaction do
        stored = post.class.lock.find(post.id)
        ImageResolution.native!(stored)
        unless stored.published?
          stored.send(:compute_derived)
          post.update_columns(stored.attributes.slice("current_revision_identifier", "word_count", "reading_time_minutes", "search_text", "body_image_manifest", "body_image_source_digest"))
          next { revision: nil, publication: nil, approval: nil }
        end

        new(stored, post, change: change, note: note, description: description, actor: actor,
          now: now, made_by_ai: made_by_ai, republishing: republishing).call
      end
    end

    def initialize(stored, original, **context)
      @post, @original, @context = stored, original, context
    end

    def call
      @post.send(:compute_derived)
      payload = RevisionPayload.new(@post)
      changed = @post.public_revision&.identifier != payload.identifier
      type = entry_type(changed)
      revision = @post.revisions.find_by(identifier: payload.identifier)
      revision_kind = revision ? "same" : "new"
      revision ||= Revision.create!(post: @post, identifier: payload.identifier, payload: payload.to_json,
        actor: @context[:actor], made_by_ai: @context[:made_by_ai], created_at: @context[:now])
      if type
        Publication.create!(post: @post, revision: revision, entry_type: type, occurred_at: @context[:now],
          released_by: @context[:actor], note: @context[:note], description: description(changed))
      end
      attributes = @post.attributes.slice("current_revision_identifier", "word_count", "reading_time_minutes", "search_text", "body_image_manifest", "body_image_source_digest")
      attributes.merge!(public_revision_id: revision.id, published_at: published_at, modified_at: modified_at)
      @original.update_columns(attributes)
      @original.association(:public_revision).reset
      { revision: revision_kind, publication: type, approval: nil }
    end

    private

    def entry_type(changed)
      return "first" unless @post.public_revision_id || @post.publications.exists?
      return @context[:change].to_s if @context[:change].present?
      return "substantive" if changed
      "maintenance" if @context[:republishing]
    end

    def description(changed)
      return @context[:description] if @context[:description].present?
      "republished" if @context[:republishing] && !changed
    end

    def published_at
      @post.publications.find_by(entry_type: "first")&.occurred_at ||
        @post.baseline&.first_published_at || @post.baseline&.declared_first_published_at
    end

    def modified_at
      @post.publications.where(entry_type: %w[substantive correction]).maximum(:occurred_at) ||
        @post.baseline&.last_modified_at || published_at
    end
  end
end
