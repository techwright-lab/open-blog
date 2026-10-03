module OpenBlog
  class RecordsSerializer
    BASELINE_FIELDS = %i[post_id adopted_at adopted_revision_id provenance provenance_evidence first_published_at
      first_published_evidence declared_first_published_at last_modified_at last_modified_evidence
      source_system source_id source_body_sha256 adopted_by].freeze
    CONNECTION_FIELDS = %i[post_id connections third_party_paid declared_by declared_on recorded_by].freeze

    def self.call(post)
      {
        revisions: post.revisions.order(:id).map { |row| fields(row, %i[identifier actor made_by_ai created_at]) },
        approvals: post.approvals.includes(:revision).order(:id).map do |row|
          fields(row, %i[kind reviewer_name facts_checked approved_at declared_on declared_by confirmed_by evidence recorded_by])
            .merge(revision_identifier: row.revision.identifier)
        end,
        publications: post.publications.includes(:revision).order(:id).map do |row|
          fields(row, %i[entry_type occurred_at released_by description note]).merge(revision_identifier: row.revision&.identifier)
        end,
        baseline: post.baseline && fields(post.baseline, BASELINE_FIELDS),
        connections: post.connection_declarations.order(:id).map { |row| fields(row, CONNECTION_FIELDS) }
      }
    end

    def self.fields(record, names)
      names.to_h { |name| [ name, record.public_send(name) ] }
    end
    private_class_method :fields
  end
end
