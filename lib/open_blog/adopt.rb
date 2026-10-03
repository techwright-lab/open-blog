module OpenBlog
  class Adopt
    autoload :Contract, "open_blog/adopt/contract"
    autoload :Snapshot, "open_blog/adopt/snapshot"

    def self.call(attributes, actor:, now: Time.current)
      contract = Contract.new(attributes, now: now)
      prepared = ImageResolution.prepare_inputs(contract.attributes)
      body_images = ImageResolution.prepare(attributes: contract.content)
      current = nil
      result = nil
      Post.transaction(requires_new: true) do
        baseline = Baseline.find_by(contract.attributes.slice(:source_system, :source_id))
        resolved = baseline ? baseline.post : PostIdentity.resolve(contract.attributes.slice(:external_id, :slug))
        current = resolved.persisted? ? Post.lock.find(resolved.id) : resolved
        result = RedirectTarget.synchronize do
          new(current, contract, prepared, actor: actor, now: now, body_images: body_images).call
        end
        raise ActiveRecord::Rollback if contract.dry_run?
      end
      result
    rescue Error => error
      failure(current, error, contract)
    rescue ActiveRecord::RecordInvalid => error
      collision = error.record.is_a?(Baseline) && %i[source_id post_id].any? do |field|
        error.record.errors.details[field].any? { |detail| detail[:error] == :taken }
      end
      refusal = collision ? Error::IdentityConflict.new : Error::ValidationFailed.new(details: error.record.errors.attribute_names.map(&:to_s))
      failure(current, refusal, contract)
    rescue ActiveRecord::RecordNotFound
      failure(current, Error::NotFound.new, contract)
    rescue ActiveRecord::RecordNotUnique
      failure(current, Error::IdentityConflict.new, contract)
    end

    def self.failure(post, error, contract)
      result = Operation.failure(post, error)
      Result.new(**result.to_h.merge(dry_run: contract&.dry_run? || false))
    end
    private_class_method :failure

    def initialize(post, contract, prepared, actor:, now:, body_images:)
      @post, @contract, @prepared, @actor, @now = post, contract, prepared, actor, now
      @body_images = body_images
      @created = post.new_record?
    end

    def call
      baseline = @post.baseline if @post.persisted?
      verify_identity(baseline)
      previous = Snapshot.stored(@post, baseline, include_connections: @contract.connections.present?)
      assign_candidate
      redirects = @contract.redirects(default_date: baseline&.adopted_at&.to_date || @now.to_date, current_slug: @post.slug)
      validate_redirects(redirects)
      candidate = Snapshot.candidate(@post, @contract, redirects)
      if previous == candidate
        @post.reload
        return result({ revision: "same", publication: nil, approval: nil, baseline: nil, redirects: 0 })
      end
      replace_records(baseline) if baseline
      @prepared.each { |field, value| @post.public_send("#{field}=", value.persist(uploaded_by: @actor)) }
      @body_images.materialize(@post, actor: @actor)
      @post.status = "draft"
      @post.publish_at = nil
      @post.save!
      fill_category_description
      revision = @post.revisions.create!(identifier: @post.current_revision_identifier,
        payload: RevisionPayload.new(@post).to_json, actor: @actor, created_at: @now)
      @post.create_baseline!(**@contract.baseline, adopted_revision: revision, adopted_at: @now, adopted_by: @actor)
      @post.publications.create!(revision: revision, entry_type: "adopted", occurred_at: @now, released_by: @actor)
      if @contract.approval
        @post.approvals.create!(**@contract.approval, revision: revision, recorded_by: @actor)
      end
      if @contract.connections && Snapshot.latest_connections(@post) != @contract.connections
        @post.connection_declarations.create!(**@contract.connections, recorded_by: @actor, created_at: @now)
      end
      write_redirects(redirects)
      published_at = @contract.baseline[:first_published_at] || @contract.baseline[:declared_first_published_at]
      @post.update_columns(status: "published", public_revision_id: revision.id, published_at: published_at,
        modified_at: @contract.baseline[:last_modified_at] || published_at)
      @post.association(:public_revision).reset
      result({ revision: "new", publication: "adopted", approval: @contract.approval&.fetch(:kind),
        baseline: baseline ? "replaced" : "new", redirects: redirects.length })
    end

    private

    def verify_identity(baseline)
      if baseline
        if !@post.published? || @post.publications.where.not(entry_type: "adopted").exists? ||
            Redirect.where(post: @post).where.not(source: "adoption").exists?
          raise Error::AlreadyChangedInGem
        end
        unless baseline.source_system == @contract.attributes[:source_system] && baseline.source_id == @contract.attributes[:source_id]
          raise Error::IdentityConflict
        end
      elsif @post.persisted? && (@post.public_revision_id || @post.revisions.exists? || @post.publications.exists? || @post.approvals.exists? || @post.connection_declarations.exists?)
        raise Error::IdentityConflict
      end
    end

    def assign_candidate
      attributes = @contract.content.except(*@prepared.keys)
      PostAttributes.assign(@post, attributes, actor: @actor, now: @now)
      @prepared.each { |field, value| @post.public_send("#{field}=", value.image) }
      @post.status = "published"
      description = @contract.attributes[:category_description]
      @post.category.description = description if @post.category && @post.category.description.blank? && description.present?
      @body_images.preview(@post)
      @post.send(:compute_derived)
      @post.valid?
      raise ActiveRecord::RecordInvalid, @post if @post.errors.any?
    end

    def fill_category_description
      @post.category.save! if @post.category&.changed?
    end

    def replace_records(baseline)
      revision_id = baseline.adopted_revision_id
      @post.update_columns(public_revision_id: nil)
      @post.association(:public_revision).reset
      @post.approvals.where(revision_id: revision_id).delete_all
      @post.publications.where(entry_type: "adopted").delete_all
      Baseline.where(id: baseline.id).delete_all
      @post.association(:baseline).reset
      @post.revisions.where(id: revision_id).delete_all
    end

    def validate_redirects(redirects)
      redirects.each do |entry|
        slug = entry[:old_path].delete_prefix("#{OpenBlog.mount_path.chomp('/')}/")
        owner = Redirect.find_by(old_path: entry[:old_path])
        occupied = Post.where(slug: slug)
        occupied = occupied.where.not(id: @post.id) if @post.persisted?
        if (Post::RESERVED_SLUGS + OpenBlog.config.route_segments.values).include?(slug) || occupied.exists? ||
            (owner && (owner.post_id != @post.id || owner.source != "adoption"))
          raise Error::SlugReserved
        end
      end
    end

    def write_redirects(redirects)
      Redirect.where(post: @post, source: "adoption").delete_all
      redirects.each { |attributes| Redirect.create!(**attributes, post: @post, source: "adoption") }
    end

    def result(records)
      if @contract.dry_run?
        %i[author category series cover_image social_image public_revision baseline faqs tags revisions approvals publications connection_declarations rich_text_rich_body].each do |name|
          @post.association(name).load_target
        end
      end
      Result.new(post: @post, created: @created, records: records, label: LabelPolicy.for(@post),
        findings: Findings.for(@post, context: { author_default_used: !@contract.attributes.key?(:author),
          approval_incomplete: @contract.approval&.fetch(:facts_checked) == false }), dry_run: @contract.dry_run?)
    end
  end
end
