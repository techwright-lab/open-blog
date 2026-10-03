module OpenBlog
  class Operation
    def self.run(post: nil, attributes: {}, actor:, now: Time.current)
      current = nil
      result = nil
      Post.transaction(requires_new: true) do
        resolved = PostIdentity.resolve(attributes, post: post)
        current = resolved.persisted? ? Post.lock.find(resolved.id) : resolved
        created = current.new_record?
        records = yield(current, created)
        result = Result.new(post: current, created: created, records: records)
      end
      result
    rescue Error => error
      failure(current, error)
    rescue ActiveRecord::RecordInvalid => error
      collision = error.record.is_a?(Post) && %i[slug external_id].any? do |field|
        error.record.errors.details[field].any? { |detail| detail[:error] == :taken }
      end
      refusal = collision ? Error::IdentityConflict.new : Error::ValidationFailed.new(details: error.record.errors.attribute_names.map(&:to_s))
      failure(current, refusal)
    rescue ActiveRecord::RecordNotFound
      failure(current, Error::NotFound.new)
    rescue ActiveRecord::RecordNotUnique
      failure(current, Error::IdentityConflict.new)
    end

    def self.failure(post, error)
      post = post.class.find_by(id: post.id) if post&.persisted?
      Result.new(post: post&.persisted? ? post : nil, error: error)
    end
  end
end
