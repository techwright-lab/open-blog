module OpenBlog
  class WritePost
    def self.call(attributes, post:, actor:, now:, publish:, authorize: nil)
      attributes = PostAttributes.normalize(attributes)
      attributes = attributes.except(:external_id) if post&.persisted?
      source = post&.persisted? ? Post.find(post.id) : PostIdentity.resolve(attributes, post: post)
      authorize&.call(source)
      image_inputs = ImageResolution.prepare_inputs(attributes)
      images = ImageResolution.prepare(attributes: attributes, post: source)
      context = {}
      Operation.run(post: post, attributes: attributes, actor: actor, now: now, context: context, authorize: authorize) do |current, created|
        old_slug, was_public = current.slug, current.published?
        context[:author_default_used] = created && !attributes.key?(:author)
        approval = attributes[:approval]
        context[:approval_incomplete] = approval.is_a?(Hash) && approval.with_indifferent_access[:facts_checked] == false
        release = publish == :preserve ? current.published? : publish
        records = RedirectTarget.synchronize do
          new(current, attributes, actor: actor, now: now, publish: release, images: images, image_inputs: image_inputs).call
        end
        context[:slug_changed] = was_public && old_slug != current.slug
        records
      end
    rescue Error => error
      Operation.failure(post, error)
    rescue ActiveRecord::RecordNotFound
      Operation.failure(post, Error::NotFound.new)
    end

    def initialize(post, attributes, actor:, now:, publish:, images:, image_inputs: {})
      @post, @attributes, @actor, @now, @publish = post, attributes, actor, now, publish
      @images, @image_inputs = images, image_inputs
    end

    def call
      raise Error::PostIsPublic if !@publish && @post.published?
      old_path = @post.path if @post.persisted?
      was_public = @post.published?
      previous_schedule = @post.publish_at
      PostAttributes.assign(@post, @attributes.except(*@image_inputs.keys), actor: @actor, now: @now)
      @image_inputs.each { |field, prepared| @post.public_send("#{field}=", prepared.image) }
      PostIdentity.resolve({ slug: @post.slug }, post: @post)
      apply_status
      validate_records
      @image_inputs.each { |field, prepared| @post.public_send("#{field}=", prepared.persist(uploaded_by: @actor)) }
      @images.materialize(@post, actor: @actor)
      @post.send(:compute_derived)
      validate_approval
      validate_change
      enforce_gates if @publish && !cancel_schedule?
      @images.preview(@post)
      @post.send(:compute_derived)
      validate_approval
      validate_change
      enforce_approval_gate if @publish && !cancel_schedule?
      @post.release_context = { actor: @actor, now: @now, change: @attributes[:change],
        note: @attributes[:note], description: @attributes[:change_description], made_by_ai: @attributes[:made_by_ai] }
      @post.save!
      records = @post.release_records || { revision: nil, publication: nil, approval: nil }
      store_approval(records) if @attributes.key?(:approval)
      store_connections if @attributes.key?(:connections)
      update_redirects(old_path, was_public)
      enqueue if @post.scheduled? && previous_schedule != @post.publish_at
      records
    ensure
      @post.release_context = nil
    end

    private

    def cancel_schedule?
      @cancel_schedule
    end

    def apply_status
      @cancel_schedule = @post.scheduled? && @attributes.key?(:publish_at) && @attributes[:publish_at].nil?
      if @attributes.key?(:publish_at)
        value = @attributes[:publish_at]
        time = value.is_a?(String) ? Time.zone.parse(value) : value
        unless value.nil? || time.respond_to?(:to_time)
          raise Error::ValidationFailed.new(details: [ "publish_at" ])
        end
        @post.publish_at = time
      end
      if @cancel_schedule
        @post.status = "draft"
      elsif @post.publish_at && @attributes.key?(:publish_at) && @post.publish_at > @now
        raise Error::ValidationFailed.new(details: [ "publish_at" ]) unless @publish || @post.scheduled?
        @post.status = "scheduled"
      elsif @publish
        @post.status = "published"
        @post.publish_at = nil
      end
    rescue ArgumentError, TypeError
      raise Error::ValidationFailed.new(details: [ "publish_at" ])
    end

    def validate_records
      if @attributes.key?(:change) && !%w[substantive correction maintenance].include?(@attributes[:change].to_s)
        raise Error::ValidationFailed.new(details: [ "change" ])
      end
      if @attributes[:change].to_s == "correction" && @attributes[:note].blank?
        raise Error::CorrectionNoteRequired
      end
      if @attributes.key?(:made_by_ai) && ![ true, false, nil ].include?(@attributes[:made_by_ai])
        raise Error::ValidationFailed.new(details: [ "made_by_ai" ])
      end
    end

    def validate_approval
      return unless @attributes.key?(:approval)
      value = @attributes[:approval]
      unless value.is_a?(Hash)
        raise Error::ApprovalIncomplete
      end
      @approval = value.symbolize_keys
      unless @approval[:name].is_a?(String) && @approval[:name].present? && [ true, false ].include?(@approval[:facts_checked])
        raise Error::ApprovalIncomplete
      end
      if @approval.key?(:revision_identifier) && @approval[:revision_identifier] != @post.current_revision_identifier
        raise Error::RevisionMismatch
      end
    end

    def validate_change
      return unless @publish && @post.published? && @post.public_revision
      if @post.public_revision.identifier != @post.current_revision_identifier && @attributes[:change].blank?
        raise Error::ChangeTypeRequired
      end
    end

    def enforce_gates
      enforce_approval_gate
      messages = OpenBlog.config.before_publish&.call(@post, { actor: @actor, now: @now, attributes: @attributes })
      raise Error::RefusedByHost.new(details: Array(messages)) if messages.present?
    end

    def enforce_approval_gate
      if OpenBlog.config.require_approval && !@post.provenance_human_written?
        approved = @approval && @approval[:facts_checked] == true
        approved ||= @post.approvals.joins(:revision).exists?(facts_checked: true, open_blog_revisions: { identifier: @post.current_revision_identifier }) if @post.persisted?
        raise Error::ApprovalRequired unless approved
      end
    end

    def store_approval(records)
      revision = @post.revisions.find_by(identifier: @post.current_revision_identifier)
      if revision
        records[:revision] ||= "same"
      else
        revision = @post.revisions.create!(identifier: @post.current_revision_identifier,
          payload: RevisionPayload.new(@post).to_json, actor: @actor, made_by_ai: @attributes[:made_by_ai], created_at: @now)
        records[:revision] = "new"
      end
      @post.approvals.create!(revision: revision, kind: "sent", reviewer_name: @approval[:name],
        facts_checked: @approval[:facts_checked], approved_at: @now, recorded_by: @actor)
      records[:approval] = "sent"
    end

    def store_connections
      input = @attributes[:connections]
      unless input.is_a?(Hash)
        raise Error::ValidationFailed.new(details: [ "connections" ])
      end
      input = input.symbolize_keys
      if (input.keys - %i[connections third_party_paid declared_by declared_on]).any? || ![ true, false ].include?(input[:third_party_paid])
        raise Error::ValidationFailed.new(details: [ "connections" ])
      end
      if input[:connections].is_a?(Array)
        input[:connections].each do |entry|
          next unless entry.is_a?(Hash)
          unknown = entry.keys.map(&:to_s) - %w[party relation]
          raise Error::UnknownField.new(details: unknown.map { |key| "connections.connections.#{key}" }) if unknown.any?
        end
      end
      input[:declared_on] = @now.to_date unless input.key?(:declared_on)
      @post.connection_declarations.create!(**input, recorded_by: @actor, created_at: @now)
    end

    def update_redirects(old_path, was_public)
      if old_path && old_path != @post.path && was_public
        redirect = Redirect.find_or_initialize_by(old_path: old_path)
        raise Error::SlugReserved if redirect.persisted? && redirect.post_id != @post.id
        if redirect.new_record?
          redirect.assign_attributes(post: @post, source: "slug_change", occurred_on: @now.to_date)
        end
        redirect.update!(new_path: @post.path)
        Redirect.where(new_path: old_path).update_all(new_path: @post.path, updated_at: @now)
      end
      if @post.published?
        Redirect.where(old_path: @post.path, post: @post).destroy_all
        Redirect.where(post: @post, source: %w[slug_change adoption unpublish removal]).update_all(new_path: @post.path, updated_at: @now)
      end
    end

    def enqueue
      id, due = @post.id, @post.publish_at
      ActiveRecord.after_all_transactions_commit do
        PublishScheduledPostJob.set(wait_until: due).perform_later(id)
      end
    end
  end
end
