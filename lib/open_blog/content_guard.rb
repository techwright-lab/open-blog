module OpenBlog
  module ContentGuard
    extend ActiveSupport::Concern

    STATE_KEY = :open_blog_content_parents

    def self.with_parent(post)
      previous = ActiveSupport::IsolatedExecutionState[STATE_KEY]
      Post.lock.find(post.id) if post.persisted?
      ActiveSupport::IsolatedExecutionState[STATE_KEY] = Array(previous) + [ post ]
      yield
    ensure
      if previous
        ActiveSupport::IsolatedExecutionState[STATE_KEY] = previous
      else
        ActiveSupport::IsolatedExecutionState.delete(STATE_KEY)
      end
    end

    def self.active?(post)
      return false unless post
      Array(ActiveSupport::IsolatedExecutionState[STATE_KEY]).any? do |parent|
        parent.equal?(post) || (parent.id && parent.id == post.id)
      end
    end

    included do
      around_save :guard_content_write, prepend: true
      around_destroy :guard_content_write, prepend: true
    end

    def update_columns(attributes)
      reject_content_bypass if content_guard_applies? || content_guard_target?(attributes)
      super
    end

    def delete
      reject_content_bypass if content_guard_applies?
      super
    end

    def increment!(attribute, by = 1, touch: nil)
      reject_content_bypass if content_guard_applies?
      super
    end

    def touch(*names, time: nil)
      if content_guard_applies? && (names.map(&:to_s) - %w[created_at updated_at]).any?
        reject_content_bypass
      end
      super
    end

    private

    def content_guard_target?(_attributes)
      false
    end

    def guard_content_write
      return yield unless content_guard_applies?
      reject_content_bypass if content_guard_identity_changed?
      parent = content_guard_parent
      return yield if ContentGuard.active?(parent)
      reject_content_bypass unless parent&.persisted?

      fresh = Post.lock.find(parent.id)
      result = yield
      RecordRelease.call(fresh) if result
      result
    end

    def reject_content_bypass
      raise ActiveRecord::ReadOnlyRecord, "Save or destroy content through its existing post association"
    end
  end
end
