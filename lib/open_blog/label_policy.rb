module OpenBlog
  class LabelPolicy
    def self.for(post)
      new(post).label
    end

    def initialize(post)
      @post = post
    end

    def label
      return :none if @post.provenance_human_written?
      notice = @post.provenance_ai_assisted? ? :ai_assisted : :ai_unknown
      return notice if @post.provenance_ai_assisted? && OpenBlog.config.ai_label == :always
      return notice unless OpenBlog.config.policy_urls[:responsible_party].present?
      return notice unless revision && @post.current_revision_identifier == revision.identifier
      return notice unless image_digests_present?
      return notice unless @post.approvals.where(revision_id: revision.id, facts_checked: true).exists?
      :none
    end

    private

    def revision
      return @revision if defined?(@revision)
      @revision = if @post.published?
        @post.public_revision
      else
        @post.revisions.find_by(identifier: @post.current_revision_identifier)
      end
    end

    def image_digests_present?
      payload = JSON.parse(revision.payload)
      images = payload["images"] if payload.is_a?(Hash)
      images.is_a?(Array) && images.all? { |entry| entry.is_a?(Hash) && entry["sha256"].present? }
    rescue JSON::ParserError
      false
    end
  end
end
