module OpenBlog
  class Adopt
    class Snapshot
      BASELINE_FIELDS = %i[source_system source_id source_body_sha256 provenance provenance_evidence first_published_at first_published_evidence last_modified_at last_modified_evidence declared_first_published_at].freeze
      APPROVAL_FIELDS = %i[kind reviewer_name facts_checked approved_at declared_on declared_by confirmed_by evidence].freeze
      CONNECTION_FIELDS = %i[connections third_party_paid declared_by declared_on].freeze
      POST_FIELDS = %w[slug body_format author_id category_id series_id series_position featured canonical_url external_id provenance provenance_evidence status].freeze

      def self.stored(post, baseline, include_connections:)
        return unless baseline
        capture(post,
          baseline: baseline.attributes.symbolize_keys.slice(*BASELINE_FIELDS),
          approvals: post.approvals.where(revision_id: baseline.adopted_revision_id).order(:id).map { |record| record.attributes.symbolize_keys.slice(*APPROVAL_FIELDS) },
          redirects: Redirect.where(post: post, source: "adoption").order(:old_path).map { |record| record.attributes.symbolize_keys.slice(:old_path, :new_path, :occurred_on) },
          connections: include_connections ? latest_connections(post) : nil)
      end

      def self.candidate(post, contract, redirects)
        approval = contract.approval && APPROVAL_FIELDS.index_with { |field| contract.approval[field] }
        capture(post, baseline: contract.baseline, approvals: [ approval ].compact,
          redirects: redirects, connections: contract.connections)
      end

      def self.latest_connections(post)
        post.connection_declarations.order(:id).last&.attributes&.symbolize_keys&.slice(*CONNECTION_FIELDS)
      end

      def self.capture(post, baseline:, approvals:, redirects:, connections:)
        { identifier: RevisionPayload.new(post).identifier, post: post.attributes.slice(*POST_FIELDS),
          category_description: post.category&.description, tags: post.taggings.reject(&:marked_for_destruction?).map(&:tag_id).sort,
          baseline: baseline, approvals: approvals, redirects: redirects, connections: connections }
      end
    end
  end
end
